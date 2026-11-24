import { readFile } from "node:fs/promises";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, test } from "vitest";
import { type FitlingCore, loadCore } from "../core/fitlingCore";
import { advancePartner, loadPartner, savePartner } from "./creature";
import { creatureRow } from "./saveCreature";

// Against the local Supabase that CI starts (never the real project); CreatureHistoryTests on iOS.
const url = process.env.VITE_SUPABASE_URL;
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const serviceKey = process.env.LOCAL_SUPABASE_SERVICE_KEY;
const today = "2026-11-24";
const loggedDays = ["2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23"];
const targets = { kcal: 2000, proteinG: 120, carbsG: 250, fatG: 70 };

describe.skipIf(!url || !key || !serviceKey)("the partner on the server", () => {
  let core: FitlingCore;
  let admin: SupabaseClient;

  beforeAll(async () => {
    const file = await readFile(new URL("../../public/fitling-core.wasm", import.meta.url));
    core = await loadCore(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer);
    admin = createClient(url!, serviceKey!, { auth: { persistSession: false } });
  });

  /** A user with a profile, a partner made on 14 November and four days logged within target. */
  async function partnerWithDays(xp = 0) {
    const email = `partner-${crypto.randomUUID()}@fitling.test`;
    const password = "lang-genoeg-wachtwoord-1";
    const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (created.error) throw created.error;
    const id = created.data.user.id;
    const stamp = "2026-11-14T10:00:00Z";
    const profile = await admin.from("profiles").insert({
      id,
      health_consent_at: stamp,
      health_consent_version: 1,
      birth_date: "1996-01-10",
      sex: "female",
      height_cm: 170,
      weight_kg: 65,
      activity_level: "moderate",
      goal: "maintain",
      kcal_target: targets.kcal,
      protein_target_g: targets.proteinG,
      carbs_target_g: targets.carbsG,
      fat_target_g: targets.fatG,
      updated_at: stamp,
    });
    if (profile.error) throw profile.error;
    const row = creatureRow({ userID: id, species: "owl", name: "Uil", colorIndex: 0, tone: "sweet", startShape: 0.3, today: "2026-11-14", now: new Date(stamp) });
    const creature = await admin.from("creatures").insert({ ...row, xp });
    if (creature.error) throw creature.error;
    const entries = await admin.from("food_entries").insert(
      loggedDays.map((day) => ({
        id: crypto.randomUUID(),
        user_id: id,
        consumed_on: day,
        meal: "lunch",
        name: "Pasta",
        quantity: 500,
        quantity_unit: "g",
        kcal: 2000,
        protein_g: 130,
        updated_at: stamp,
      })),
    );
    if (entries.error) throw entries.error;
    const client = createClient(url!, key!, { auth: { persistSession: false } });
    const signIn = await client.auth.signInWithPassword({ email, password });
    if (signIn.error) throw signIn.error;
    return { id, client };
  }

  async function stored(id: string) {
    const { data, error } = await admin.from("creatures").select("xp, last_processed_on, updated_at, body_shape").eq("user_id", id).single();
    if (error) throw error;
    return data;
  }

  test("advanceIsAppliedAndSavedOnce", async () => {
    const { id, client } = await partnerWithDays();
    const now = new Date("2026-11-24T08:00:00Z");
    const { partner } = await advancePartner(client, core, id, today, now);
    const row = await stored(id);
    expect(row.last_processed_on).toBe("2026-11-23");
    expect(row.xp).toBeGreaterThan(0);
    expect(row.xp).toBe(partner?.state.xp);
    expect(new Date(row.updated_at).getTime()).toBe(now.getTime());
  });

  test("advancingTwiceWritesOnce", async () => {
    const { id, client } = await partnerWithDays();
    const first = new Date("2026-11-24T08:00:00Z");
    await advancePartner(client, core, id, today, first);
    const again = await advancePartner(client, core, id, today, new Date("2026-11-24T09:00:00Z"));
    expect(again.events).toEqual([]);
    expect(new Date((await stored(id)).updated_at).getTime()).toBe(first.getTime());
  });

  test("finishedDaysAreReportedOnce", async () => {
    // One XP short of the next level, so the first finished day levels the partner up.
    const start = await partnerWithDays();
    const partner = await loadPartner(start.client, start.id);
    const snapshot = core.partnerSnapshot({ creature: partner!.state, entries: [], workoutDays: [], periods: [], fallback: targets, today });
    const { id, client } = await partnerWithDays(snapshot.xpForNextLevel - 1);
    const once = await advancePartner(client, core, id, today, new Date("2026-11-24T08:00:00Z"));
    expect(once.events.some((event) => event.kind === "leveledUp")).toBe(true);
    const twice = await advancePartner(client, core, id, today, new Date("2026-11-24T09:00:00Z"));
    expect(twice.events).toEqual([]);
  });

  test("changesOnThePartnerTabAreSaved", async () => {
    const { id, client } = await partnerWithDays();
    const now = new Date("2026-11-24T10:00:00Z");
    await savePartner(client, id, { name: "Pluim", tone: "coach", colorIndex: 1, items: ["scarf"] }, now);
    const partner = await loadPartner(client, id);
    expect(partner).toMatchObject({ name: "Pluim", items: ["scarf"], state: { tone: "coach", colorIndex: 1 } });
    expect(new Date((await stored(id)).updated_at).getTime()).toBe(now.getTime());
  });
});
