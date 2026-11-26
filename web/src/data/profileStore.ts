import type { SupabaseClient } from "@supabase/supabase-js";
import type { Activity, DailyPlanInput, Goal, ProfileRules, Sex, Targets } from "../core/fitlingCore";
import { failure } from "./failure";
import { keep, kept } from "./offline";

export type Body = Omit<DailyPlanInput, "today">;

/** The user's profile as Dagdoel uses it (UserProfile on iOS). */
export interface Profile {
  id: string;
  body: Body;
  targets: Targets;
  targetsAreManual: boolean;
}

const columns =
  "id, birth_date, sex, height_cm, weight_kg, activity_level, goal, kcal_target, protein_target_g, carbs_target_g, fat_target_g, targets_are_manual";

interface Row {
  id: string;
  birth_date: string;
  sex: Sex;
  height_cm: number;
  weight_kg: number;
  activity_level: Activity;
  goal: Goal;
  kcal_target: number;
  protein_target_g: number;
  carbs_target_g: number;
  fat_target_g: number;
  targets_are_manual: boolean;
}

/** The profile; without a connection the one this browser last read. */
export async function loadProfile(client: SupabaseClient, userID: string): Promise<Profile> {
  return kept("profile", () => profileFromServer(client, userID));
}

async function profileFromServer(client: SupabaseClient, userID: string): Promise<Profile> {
  const { data, error } = await client.from("profiles").select(columns).eq("id", userID).maybeSingle<Row>();
  if (error) throw failure(error);
  if (!data) throw new Error("error.server");
  return {
    id: data.id,
    body: {
      birthDay: data.birth_date,
      sex: data.sex,
      heightCm: Number(data.height_cm),
      weightKg: Number(data.weight_kg),
      activityLevel: data.activity_level,
      goal: data.goal,
    },
    targets: { kcal: data.kcal_target, proteinG: data.protein_target_g, carbsG: data.carbs_target_g, fatG: data.fat_target_g },
    targetsAreManual: data.targets_are_manual,
  };
}

function same(a: Targets, b: Targets): boolean {
  return a.kcal === b.kcal && a.proteinG === b.proteinG && a.carbsG === b.carbsG && a.fatG === b.fatG;
}

/**
 * An edited profile, as ProfileViewModel.saveProfile: targets that follow the plan move with it, targets the user set
 * by hand stay and the user is asked whether to recalculate them. `planned` is the plan for the edited body.
 */
export function editedProfile(profile: Profile, body: Body, planned: Targets): { profile: Profile; newTargets?: Targets; askRecalculate: boolean } {
  const follows = !profile.targetsAreManual && !same(planned, profile.targets);
  return {
    profile: { ...profile, body, targets: follows ? planned : profile.targets },
    newTargets: follows ? planned : undefined,
    askRecalculate: profile.targetsAreManual,
  };
}

export type TargetField = "kcal" | "protein" | "carbs" | "fat";

/** The first typed target the database would refuse, as ProfileViewModel.TargetsError.outOfRange. */
export function outOfRange(targets: Targets, limits: ProfileRules["targetLimits"]): TargetField | undefined {
  const fields: [keyof Targets, TargetField][] = [
    ["kcal", "kcal"],
    ["proteinG", "protein"],
    ["carbsG", "carbs"],
    ["fatG", "fat"],
  ];
  return fields.find(([key]) => {
    const [lowest, highest] = limits[key];
    return !Number.isInteger(targets[key]) || targets[key] < lowest || targets[key] > highest;
  })?.[1];
}

/**
 * New targets hold from today on and earlier days keep theirs; a second change on the same day updates that day's
 * period (LocalData.recordTargets).
 */
async function recordTargets(client: SupabaseClient, userID: string, targets: Targets, today: string, moment: string) {
  const existing = await client
    .from("target_history")
    .select("id")
    .eq("user_id", userID)
    .eq("effective_on", today)
    .is("deleted_at", null)
    .order("updated_at", { ascending: false })
    .limit(1);
  if (existing.error) throw failure(existing.error);
  const values = {
    kcal_target: targets.kcal,
    protein_target_g: targets.proteinG,
    carbs_target_g: targets.carbsG,
    fat_target_g: targets.fatG,
    updated_at: moment,
  };
  const period = existing.data[0];
  const write = period
    ? await client.from("target_history").update(values).eq("id", period.id)
    : await client.from("target_history").insert({ id: crypto.randomUUID(), user_id: userID, effective_on: today, ...values });
  if (write.error) throw failure(write.error);
}

/** Stores the profile as it is now. New targets go into their period first, as onboarding does. */
export async function saveProfile(client: SupabaseClient, profile: Profile, change: { newTargets?: Targets; today: string; now: Date }) {
  const moment = change.now.toISOString();
  if (change.newTargets) await recordTargets(client, profile.id, change.newTargets, change.today, moment);
  const { error } = await client
    .from("profiles")
    .update({
      birth_date: profile.body.birthDay,
      sex: profile.body.sex,
      height_cm: profile.body.heightCm,
      weight_kg: profile.body.weightKg,
      activity_level: profile.body.activityLevel,
      goal: profile.body.goal,
      kcal_target: profile.targets.kcal,
      protein_target_g: profile.targets.proteinG,
      carbs_target_g: profile.targets.carbsG,
      fat_target_g: profile.targets.fatG,
      targets_are_manual: profile.targetsAreManual,
      updated_at: moment,
    })
    .eq("id", profile.id);
  if (error) throw failure(error);
  // What this browser shows without a connection is what was just saved, not the read before it.
  keep("profile", profile);
}

/**
 * The target periods, for the target that applied on a day (TargetPeriods in FitlingCore); without a connection the
 * ones this browser last read.
 */
export async function loadTargetPeriods(client: SupabaseClient): Promise<{ effectiveOn: string; updatedAtMs: number; targets: Targets }[]> {
  return kept("periods", () => periodsFromServer(client));
}

async function periodsFromServer(client: SupabaseClient): Promise<{ effectiveOn: string; updatedAtMs: number; targets: Targets }[]> {
  const { data, error } = await client
    .from("target_history")
    .select("effective_on, updated_at, kcal_target, protein_target_g, carbs_target_g, fat_target_g")
    .is("deleted_at", null);
  if (error) throw failure(error);
  return (data as Record<string, unknown>[]).map((row) => ({
    effectiveOn: row.effective_on as string,
    updatedAtMs: Date.parse(row.updated_at as string),
    targets: {
      kcal: row.kcal_target as number,
      proteinG: row.protein_target_g as number,
      carbsG: row.carbs_target_g as number,
      fatG: row.fat_target_g as number,
    },
  }));
}
