import type { SupabaseClient } from "@supabase/supabase-js";
import type { DailyPlanInput, Targets } from "../core/fitlingCore";

/** Raise when the consent text changes in substance (HealthConsent.currentVersion on iOS). */
export const healthConsentVersion = 1;

export interface FinishedOnboarding {
  userID: string;
  profile: Omit<DailyPlanInput, "today">;
  targets: Targets;
  today: string;
  now: Date;
}

/** The rows onboarding stores, as OnboardingViewModel.finish does: the profile and the first target period. */
export function onboardingRows({ userID, profile, targets, today, now }: FinishedOnboarding) {
  const moment = now.toISOString();
  return {
    period: {
      id: crypto.randomUUID(),
      user_id: userID,
      effective_on: today,
      kcal_target: targets.kcal,
      protein_target_g: targets.proteinG,
      carbs_target_g: targets.carbsG,
      fat_target_g: targets.fatG,
      updated_at: moment,
    },
    profile: {
      id: userID,
      health_consent_at: moment,
      health_consent_version: healthConsentVersion,
      birth_date: profile.birthDay,
      sex: profile.sex,
      height_cm: profile.heightCm,
      weight_kg: profile.weightKg,
      activity_level: profile.activityLevel,
      goal: profile.goal,
      kcal_target: targets.kcal,
      protein_target_g: targets.proteinG,
      carbs_target_g: targets.carbsG,
      fat_target_g: targets.fatG,
      targets_are_manual: false,
      updated_at: moment,
    },
  };
}

/**
 * Stores onboarding. The target period goes first: users cannot delete rows, and a period without a profile does
 * no harm (the app still shows onboarding), while a profile without its period would.
 */
export async function finishOnboarding(client: SupabaseClient, finished: FinishedOnboarding): Promise<void> {
  const rows = onboardingRows(finished);
  const period = await client.from("target_history").insert(rows.period);
  if (period.error) throw new Error("error.server");
  const profile = await client.from("profiles").insert(rows.profile);
  if (profile.error) throw new Error("error.server");
}
