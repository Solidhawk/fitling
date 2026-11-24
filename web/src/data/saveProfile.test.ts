import { expect, test } from "vitest";
import { healthConsentVersion, onboardingRows } from "./saveProfile";

test("onboarding stores the profile and a target period from today, with the same moment", () => {
  const rows = onboardingRows({
    userID: "u1",
    profile: { birthDay: "1996-01-10", sex: "male", heightCm: 180, weightKg: 80, activityLevel: "moderate", goal: "maintain" },
    targets: { kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77 },
    today: "2026-11-24",
    now: new Date("2026-11-24T10:00:00Z"),
  });
  expect(rows.profile).toMatchObject({
    id: "u1",
    health_consent_version: healthConsentVersion,
    birth_date: "1996-01-10",
    activity_level: "moderate",
    goal: "maintain",
    kcal_target: 2760,
    protein_target_g: 128,
    targets_are_manual: false,
    updated_at: "2026-11-24T10:00:00.000Z",
  });
  expect(rows.profile.health_consent_at).toBe(rows.profile.updated_at);
  expect(rows.period).toMatchObject({ user_id: "u1", effective_on: "2026-11-24", kcal_target: 2760, fat_target_g: 77 });
  expect(rows.period.updated_at).toBe(rows.profile.updated_at);
});
