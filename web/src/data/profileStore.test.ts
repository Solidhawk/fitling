import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, test } from "vitest";
import type { ProfileRules } from "../core/fitlingCore";
import { editedProfile, loadProfile, outOfRange, type Profile, saveProfile } from "./profileStore";

const limits: ProfileRules["targetLimits"] = { kcal: [1, 20000], proteinG: [0, 1000], carbsG: [0, 5000], fatG: [0, 2000] };
const profile: Profile = {
  id: "u1",
  body: { birthDay: "1996-01-10", sex: "male", heightCm: 180, weightKg: 80, activityLevel: "moderate", goal: "maintain" },
  targets: { kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77 },
  targetsAreManual: false,
};
const planned = { kcal: 3000, proteinG: 144, carbsG: 420, fatG: 83 };

// ProfileViewModelTests on iOS.
test("editingProfileRecalculatesAutoTargets", () => {
  const body = { ...profile.body, weightKg: 90 };
  const edit = editedProfile(profile, body, planned);
  expect(edit).toEqual({ profile: { ...profile, body, targets: planned }, newTargets: planned, askRecalculate: false });
});

test("editingTheProfileWithoutNewTargetsAddsNoPeriod", () => {
  const body = { ...profile.body, birthDay: "1996-01-03" };
  const edit = editedProfile(profile, body, profile.targets);
  expect(edit.newTargets).toBeUndefined();
  expect(edit.profile.body.birthDay).toBe("1996-01-03");
});

test("editingProfileWithManualTargetsAsks", () => {
  const manual = { ...profile, targetsAreManual: true };
  const edit = editedProfile(manual, { ...profile.body, weightKg: 90 }, planned);
  expect(edit.askRecalculate).toBe(true);
  expect(edit.newTargets).toBeUndefined();
  expect(edit.profile.targets.kcal).toBe(2760);
});

test("saveTargetsOutOfRangeThrows", () => {
  expect(outOfRange({ kcal: 0, proteinG: 100, carbsG: 200, fatG: 60 }, limits)).toBe("kcal");
  expect(outOfRange({ kcal: 2000, proteinG: 1001, carbsG: 200, fatG: 60 }, limits)).toBe("protein");
  expect(outOfRange({ kcal: 2000, proteinG: 100, carbsG: 200, fatG: 60 }, limits)).toBeUndefined();
  expect(outOfRange({ kcal: 2000.5, proteinG: 100, carbsG: 200, fatG: 60 }, limits)).toBe("kcal");
});

// Against the local Supabase that CI starts (never the real project). Without it these tests cannot run.
const url = process.env.VITE_SUPABASE_URL;
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const serviceKey = process.env.LOCAL_SUPABASE_SERVICE_KEY;

describe.skipIf(!url || !key || !serviceKey)("on the server", () => {
  async function signedIn() {
    const admin = createClient(url!, serviceKey!, { auth: { persistSession: false } });
    const email = `profile-${crypto.randomUUID()}@fitling.test`;
    const password = "lang-genoeg-wachtwoord-1";
    const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (created.error) throw created.error;
    const id = created.data.user.id;
    const now = new Date().toISOString();
    const row = await admin.from("profiles").insert({
      id,
      health_consent_at: now,
      health_consent_version: 1,
      birth_date: "1996-01-10",
      sex: "male",
      height_cm: 180,
      weight_kg: 80,
      activity_level: "moderate",
      goal: "maintain",
      kcal_target: 2760,
      protein_target_g: 128,
      carbs_target_g: 389,
      fat_target_g: 77,
      updated_at: now,
    });
    if (row.error) throw row.error;
    const client = createClient(url!, key!, { auth: { persistSession: false } });
    const signIn = await client.auth.signInWithPassword({ email, password });
    if (signIn.error) throw signIn.error;
    return { id, client, admin };
  }

  async function periods(admin: SupabaseClient, id: string) {
    const { data } = await admin.from("target_history").select("effective_on, kcal_target").eq("user_id", id).order("effective_on");
    return data;
  }

  test("changingTargetsStartsANewPeriodToday", async () => {
    const { id, client, admin } = await signedIn();
    await admin.from("target_history").insert({
      user_id: id,
      effective_on: "2026-11-14",
      kcal_target: 2760,
      protein_target_g: 128,
      carbs_target_g: 389,
      fat_target_g: 77,
      updated_at: "2026-11-14T10:00:00Z",
    });
    const stored = await loadProfile(client, id);
    expect(stored.body.weightKg).toBe(80);
    const targets = { kcal: 2500, proteinG: 150, carbsG: 300, fatG: 70 };
    await saveProfile(client, { ...stored, targets, targetsAreManual: true }, { newTargets: targets, today: "2026-11-24", now: new Date() });
    expect(await periods(admin, id)).toEqual([
      { effective_on: "2026-11-14", kcal_target: 2760 },
      { effective_on: "2026-11-24", kcal_target: 2500 },
    ]);
    const again = await loadProfile(client, id);
    expect(again.targets).toEqual(targets);
    expect(again.targetsAreManual).toBe(true);
  });

  test("changingTargetsTwiceOnOneDayKeepsOnePeriod", async () => {
    const { id, client, admin } = await signedIn();
    const stored = await loadProfile(client, id);
    const first = { kcal: 2500, proteinG: 150, carbsG: 300, fatG: 70 };
    const second = { kcal: 2400, proteinG: 150, carbsG: 280, fatG: 70 };
    await saveProfile(client, { ...stored, targets: first }, { newTargets: first, today: "2026-11-24", now: new Date() });
    await saveProfile(client, { ...stored, targets: second }, { newTargets: second, today: "2026-11-24", now: new Date() });
    expect(await periods(admin, id)).toEqual([{ effective_on: "2026-11-24", kcal_target: 2400 }]);
  });
});
