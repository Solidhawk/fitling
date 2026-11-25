import type { SupabaseClient } from "@supabase/supabase-js";
import type { CreatureStateInput, FitlingCore, IsoDay, PartnerDays, PartnerEvent } from "../core/fitlingCore";
import { addDays } from "../day";
import type { Species } from "../partner/species";
import { entriesBetween, workoutDaysBetween } from "./diary";
import { failure } from "./failure";
import { keep, kept, noNetwork } from "./offline";
import { loadProfile, loadTargetPeriods } from "./profileStore";

/** The user's partner as stored: what FitlingCore needs for its mood, plus its name and what it wears. */
export interface Partner {
  species: Species;
  name: string;
  state: CreatureStateInput;
  items: string[];
}

/** The partner; without a connection the one this browser last knew. */
export async function loadPartner(client: SupabaseClient, userID: string): Promise<Partner | undefined> {
  return kept("partner", () => partnerFromServer(client, userID));
}

async function partnerFromServer(client: SupabaseClient, userID: string): Promise<Partner | undefined> {
  const { data, error } = await client
    .from("creatures")
    .select("species, name, color_index, tone, created_on, body_shape, xp, last_processed_on, off_target_days, equipped_items")
    .eq("user_id", userID)
    .maybeSingle();
  if (error) throw failure(error);
  if (!data) return undefined;
  return {
    species: data.species as Species,
    name: data.name as string,
    items: (data.equipped_items as string[] | null) ?? [],
    state: {
      species: data.species as string,
      colorIndex: data.color_index as number,
      tone: data.tone as string,
      createdOn: data.created_on as string,
      bodyShape: Number(data.body_shape),
      xp: data.xp as number,
      lastProcessedDay: (data.last_processed_on as string | null) ?? undefined,
      offTargetDays: data.off_target_days as number,
    },
  };
}

/**
 * Folds every finished day into the partner's shape and XP, as CreatureHistory.update on iOS, and writes only when that
 * changed something. The same row and days give the same result, so a phone that folds the same days writes the same.
 * Without a connection nothing is folded: the partner stays as it was, and the days are folded once it is back.
 */
export async function advancePartner(
  client: SupabaseClient,
  core: FitlingCore,
  userID: string,
  today: IsoDay,
  now: Date,
): Promise<{ partner?: Partner; events: PartnerEvent[] }> {
  const partner = await loadPartner(client, userID);
  if (!partner) return { events: [] };
  if (noNetwork()) return { partner, events: [] };
  try {
    return await fold(client, core, userID, partner, today, now);
  } catch (error) {
    if (error instanceof Error && error.message === "error.network") return { partner, events: [] };
    throw error;
  }
}

async function fold(
  client: SupabaseClient,
  core: FitlingCore,
  userID: string,
  partner: Partner,
  today: IsoDay,
  now: Date,
): Promise<{ partner?: Partner; events: PartnerEvent[] }> {
  const { firstDay } = core.advanceFrom({ creature: partner.state });
  const [entries, workoutDays, periods, profile] = await Promise.all([
    entriesBetween(client, firstDay, today),
    workoutDaysBetween(client, firstDay, today),
    loadTargetPeriods(client),
    loadProfile(client, userID),
  ]);
  const result = core.partnerAdvance({
    creature: partner.state,
    entries: entries.map((entry) => ({ day: entry.consumedOn, kcal: entry.kcal, proteinG: entry.proteinG })),
    workoutDays,
    periods,
    fallback: profile.targets,
    today,
  });
  if (!result.changed) return { partner, events: [] };
  const state = result.creature;
  const { data, error } = await client
    .from("creatures")
    .update({
      xp: state.xp,
      body_shape: state.bodyShape,
      last_processed_on: state.lastProcessedDay ?? null,
      off_target_days: state.offTargetDays,
      updated_at: now.toISOString(),
    })
    .eq("user_id", userID)
    .select("user_id");
  if (error) throw failure(error);
  // The server sets an update aside when another device wrote later (last writer wins): then nothing was folded
  // here, and the news would come again with the next fold.
  if (!data || data.length === 0) return { partner, events: [] };
  const folded = { ...partner, state };
  keep("partner", folded);
  return { partner: folded, events: result.events };
}

/** A change the user made on the partner tab: colour, name, voice or what it wears. */
export async function savePartner(
  client: SupabaseClient,
  userID: string,
  change: Partial<{ colorIndex: number; name: string; tone: string; items: string[] }>,
  now: Date,
): Promise<void> {
  const row: Record<string, unknown> = { updated_at: now.toISOString() };
  if (change.colorIndex !== undefined) row.color_index = change.colorIndex;
  if (change.name !== undefined) row.name = change.name;
  if (change.tone !== undefined) row.tone = change.tone;
  if (change.items !== undefined) row.equipped_items = change.items;
  const { error } = await client.from("creatures").update(row).eq("user_id", userID);
  if (error) throw failure(error);
}

/** The days partnerSnapshot is given: more than the eight it looks at, which it picks itself. */
const weekDays = 14;

/**
 * What the partner did the last two weeks, for its mood today. Without a connection: what was eaten as this browser
 * knows it, and the workouts of the last two weeks it read.
 */
export async function partnerWeek(client: SupabaseClient, today: IsoDay): Promise<Pick<PartnerDays, "entries" | "workoutDays">> {
  const first = addDays(today, -weekDays);
  const [entries, workouts] = await Promise.all([
    entriesBetween(client, first, today),
    kept("weekWorkouts", () => workoutDaysBetween(client, first, today)),
  ]);
  const workoutDays = workouts.filter((day) => day >= first && day <= today);
  return { entries: entries.map((entry) => ({ day: entry.consumedOn, kcal: entry.kcal, proteinG: entry.proteinG })), workoutDays };
}
