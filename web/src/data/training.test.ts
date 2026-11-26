import { readFile } from "node:fs/promises";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, test } from "vitest";
import { type FitlingCore, loadCore, type TrainingInput } from "../core/fitlingCore";
import { addMeasurement, deleteMeasurement, loadMeasurements } from "./body";
import { composeWorkout, copyProgram, discardWorkout, loadTraining, logSet, startWorkout, type TrainingRows } from "./training";

// Against the local Supabase that CI starts, with the shared catalogue of supabase/seed/sport.sql (never the real
// project); TrainingTests and ComposedTrainingTests on iOS.
const url = process.env.VITE_SUPABASE_URL;
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const serviceKey = process.env.LOCAL_SUPABASE_SERVICE_KEY;
const today = "2026-11-24";

describe.skipIf(!url || !key || !serviceKey)("training on the server", () => {
  let core: FitlingCore;
  let admin: SupabaseClient;

  beforeAll(async () => {
    const file = await readFile(new URL("../../public/fitling-core.wasm", import.meta.url));
    core = await loadCore(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer);
    admin = createClient(url!, serviceKey!, { auth: { persistSession: false } });
  });

  async function user() {
    const email = `training-${crypto.randomUUID()}@fitling.test`;
    const password = "lang-genoeg-wachtwoord-1";
    const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (created.error) throw created.error;
    const client = createClient(url!, key!, { auth: { persistSession: false } });
    const signIn = await client.auth.signInWithPassword({ email, password });
    if (signIn.error) throw signIn.error;
    return { id: created.data.user.id, client };
  }

  function input(userID: string, rows: TrainingRows): TrainingInput {
    return { userID, today, languages: ["nl"], ...rows };
  }

  test("copyingAProgramMakesItYours", async () => {
    const { id, client } = await user();
    const before = await loadTraining(client);
    const shared = before.programs.find((program) => program.ownerID === undefined && !program.deleted)!;
    const ids = new Map<string, string>();
    const copyID = await copyProgram(client, id, before, shared.id, { name: "Mijn schema", language: "nl" }, new Date(), ids);
    // Again with the same ids, as after a failure: still one copy, with its days and exercises once.
    expect(await copyProgram(client, id, before, shared.id, { name: "Mijn schema", language: "nl" }, new Date(), ids)).toBe(copyID);
    const after = await loadTraining(client);
    expect(after.programs.filter((program) => program.ownerID === id)).toHaveLength(1);
    const copy = after.programs.find((program) => program.id === copyID)!;
    expect(copy).toMatchObject({ ownerID: id, name: { nl: "Mijn schema" }, daysPerWeek: shared.daysPerWeek });
    const byPosition = (a: { position: number }, b: { position: number }) => a.position - b.position;
    const sharedDays = before.days.filter((day) => day.programID === shared.id).sort(byPosition);
    const copiedDays = after.days.filter((day) => day.programID === copyID).sort(byPosition);
    expect(copiedDays.map((day) => day.name)).toEqual(sharedDays.map((day) => day.name));
    const count = (rows: TrainingRows, dayIDs: string[]) => rows.items.filter((item) => dayIDs.includes(item.programDayID)).length;
    expect(count(after, copiedDays.map((day) => day.id))).toBe(count(before, sharedDays.map((day) => day.id)));
    // The shared original is as it was.
    expect(after.days.filter((day) => day.programID === shared.id).sort(byPosition)).toEqual(sharedDays);
  });

  test("discardingRemovesTheSetsAndTheComposedDay", async () => {
    const { id, client } = await user();
    const rows = await loadTraining(client);
    const plan = core.composePlan({ training: input(id, rows), focus: "upper_body", minutes: 30 });
    expect(plan.exercises.length).toBeGreaterThan(0);
    const dayID = await composeWorkout(client, id, rows, plan, { program: "Samengesteld", day: "Bovenlichaam", language: "nl" }, new Date());
    const sessionID = await startWorkout(client, id, dayID, today, new Date());
    await logSet(client, id, { sessionID, exerciseID: plan.exercises[0].exerciseID, position: 0, weightKg: 40, reps: 10, isWarmup: false }, new Date());
    const started = await loadTraining(client);
    expect(started.sets).toHaveLength(1);
    const cleanup = core.discardCleanup({ training: input(id, started), sessionID });
    expect(cleanup.dayID).toBe(dayID);
    await discardWorkout(client, sessionID, cleanup, new Date());
    const after = await loadTraining(client);
    expect(after.sessions).toEqual([]);
    expect(after.sets).toEqual([]);
    expect(after.days.find((day) => day.id === dayID)?.deleted).toBe(true);
    expect(after.programs.find((program) => program.id === cleanup.programID)?.deleted).toBe(true);
    expect(after.items.filter((item) => item.programDayID === dayID)).toEqual([]);
  });

  test("measurementsAreSavedAndDeleted", async () => {
    const { id, client } = await user();
    const stored = core.measurementStored({ value: 176, kind: "weight", usesMetric: false }).value!;
    expect(await addMeasurement(client, id, { kind: "weight", value: stored, day: today, today }, new Date())).toBe(true);
    // A day still to come is refused (BodyLog.add).
    expect(await addMeasurement(client, id, { kind: "weight", value: stored, day: "2026-11-25", today }, new Date())).toBe(false);
    const saved = await loadMeasurements(client, "weight");
    expect(saved).toEqual([{ id: saved[0].id, measuredOn: today, kind: "weight", value: 79.8 }]);
    await deleteMeasurement(client, saved[0].id, new Date());
    expect(await loadMeasurements(client, "weight")).toEqual([]);
  });
});
