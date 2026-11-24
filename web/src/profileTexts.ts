import type { Activity, Goal } from "./core/fitlingCore";

// The catalog keys of the profile's choices and of the target warnings, as titleKey and messageKey on iOS.

export const activityKeys: Record<Activity, string> = {
  sedentary: "onboarding.activity.sedentary",
  light: "onboarding.activity.light",
  moderate: "onboarding.activity.moderate",
  active: "onboarding.activity.active",
  very_active: "onboarding.activity.veryActive",
};

export const goalKeys: Record<Goal, string> = {
  lose: "onboarding.goal.lose",
  build_muscle: "onboarding.goal.buildMuscle",
  maintain: "onboarding.goal.maintain",
  recomp: "onboarding.goal.recomp",
};

/** In the order of TargetWarning.allCases. */
export const warningKeys: Record<string, string> = {
  below_floor: "targets.warning.belowFloor",
  below_common_minimum: "targets.warning.low",
  large_deficit: "targets.warning.largeDeficit",
};

/** The warnings FitlingCore found, in the app's order. */
export function orderedWarnings(found: string[]): string[] {
  return Object.keys(warningKeys).filter((warning) => found.includes(warning));
}
