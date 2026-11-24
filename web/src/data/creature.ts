import type { SupabaseClient } from "@supabase/supabase-js";
import type { CreatureStateInput, FitlingCore, IsoDay, PartnerEvent } from "../core/fitlingCore";
import type { Species } from "../partner/species";
import { entriesBetween, workoutDaysBetween } from "./diary";
import { failure } from "./failure";
import { loadProfile, loadTargetPeriods } from "./profileStore";

/** The user's partner as stored: what FitlingCore needs for its mood, plus its name and what it wears. */
export interface Partner {
  species: Species;
  name: string;
  state: CreatureStateInput;
  items: string[];
}

export async function loadPartner(client: SupabaseClient, userID: string): Promise<Partner | undefined> {
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
  const { error } = await client
    .from("creatures")
    .update({
      xp: state.xp,
      body_shape: state.bodyShape,
      last_processed_on: state.lastProcessedDay ?? null,
      off_target_days: state.offTargetDays,
      updated_at: now.toISOString(),
    })
    .eq("user_id", userID);
  if (error) throw failure(error);
  return { partner: { ...partner, state }, events: result.events };
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
