import { readFile } from "node:fs/promises";
import { expect, test } from "vitest";
import { type DailyPlanInput, loadCore } from "./fitlingCore";

// Built by CI from web/core (swift build --swift-sdk wasm32-unknown-wasi).
const file = await readFile(new URL("../../public/fitling-core.wasm", import.meta.url));
const wasm = file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer;

// The profile of NutritionEngineTests.maintenanceTargetEqualsTotalExpenditure.
const maintain: DailyPlanInput = {
  birthDay: "1996-01-10",
  sex: "male",
  heightCm: 180,
  weightKg: 80,
  activityLevel: "moderate",
  goal: "maintain",
  today: "2026-11-18",
};

test("the daily plan is the one of the app", async () => {
  const core = await loadCore(wasm);
  const plan = core.dailyPlan(maintain);
  expect(plan.targets).toEqual({ kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77 });
  expect(plan.bmr).toBeCloseTo(1780, 4);
  expect(plan.floorApplied).toBe(false);
  expect(plan.warnings).toEqual([]);
});

test("an absurd weight is an error with a message, not a trap", async () => {
  const core = await loadCore(wasm);
  expect(() => core.dailyPlan({ ...maintain, weightKg: 1e300 })).toThrow(/weightKg/);
});

test("an unknown goal is an error, not a crash", async () => {
  const core = await loadCore(wasm);
  expect(() => core.dailyPlan({ ...maintain, goal: "x" as DailyPlanInput["goal"] })).toThrow();
  // The module still answers after a failure.
  expect(core.dailyPlan(maintain).targets.kcal).toBe(2760);
});

// Every visitor downloads this file before the numbers appear; on a phone that has to stay small. The
// web app downloads the gzipped file and unpacks it with DecompressionStream.
test("the download is at most 4 MB", async () => {
  const packed = await readFile(new URL("../../public/fitling-core.wasm.gz", import.meta.url));
  expect(packed.byteLength).toBeLessThanOrEqual(4 * 1024 * 1024);
});

// The calls of web fase 1, with the numbers of the Swift tests (CallsTests).
test("body input in feet, inches and pounds", async () => {
  const core = await loadCore(wasm);
  const body = core.bodyInput({ usesMetric: false, fields: { feet: 5, inches: 11, weight: 176 } });
  expect(body).toMatchObject({ heightCm: 180.3, weightKg: 79.8, isValid: true });
});

test("birth day, macros, shares and warnings", async () => {
  const core = await loadCore(wasm);
  expect(core.birthDay({ birthDay: "1996-01-10", today: "2026-11-18" })).toEqual({ age: 30, isAdult: true, isValid: true });
  const targets = core.macros({ kcal: 2760, weightKg: 80, goal: "maintain" });
  expect(targets).toEqual({ kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77 });
  expect(core.kcalShares(targets).protein).toBeCloseTo(512 / 2760, 4);
  expect(core.warnings({ kcal: 2760, bmr: 1780, tdee: 2759, sex: "male" })).toEqual({ warnings: [], commonMinimumKcal: 1500 });
});

test("the target of a day and a new partner", async () => {
  const core = await loadCore(wasm);
  const second = { kcal: 2500, proteinG: 150, carbsG: 300, fatG: 80 };
  const targets = core.targetsOnDay({
    day: "2026-11-10",
    fallback: { kcal: 2000, proteinG: 100, carbsG: 250, fatG: 70 },
    periods: [
      { effectiveOn: "2026-11-10", updatedAtMs: 1000, targets: { kcal: 2200, proteinG: 120, carbsG: 270, fatG: 75 } },
      { effectiveOn: "2026-11-10", updatedAtMs: 2000, targets: second },
    ],
  });
  expect(targets).toEqual(second);
  expect(core.creature({ level: 1 })).toEqual({ startShape: 0.3, colorCount: 3, growthStage: 0 });
});

test("the rules Dagdoel shows and the ranges of typed targets", async () => {
  const core = await loadCore(wasm);
  const rules = core.profileRules();
  expect(rules.activityFactors.moderate).toBe(1.55);
  expect(rules.proteinPerKg.maintain).toBe(1.6);
  expect(rules.targetLimits).toEqual({ kcal: [1, 20000], proteinG: [0, 1000], carbsG: [0, 5000], fatG: [0, 2000] });
});

test("the rules for Vandaag and logging (web phase 2)", async () => {
  const core = await loadCore(wasm);
  expect(core.searchKey({ text: "  Crème Brûlée " })).toEqual({ key: "creme brulee" });
  expect(core.barcode({ text: "036000291452" })).toEqual({ gtin: "0036000291452" });
  expect(core.barcode({ text: "8712100849085" })).toEqual({});
  const a = "8c1f0a52-5d0e-4c2b-9a51-6f2f7f5d2a10";
  const b = "0b5a1c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d";
  expect(
    core.recentProducts({
      logged: [
        { productID: a, updatedAtMs: 1000 },
        { productID: b, updatedAtMs: 2000 },
        { productID: a, updatedAtMs: 3000 },
      ],
    }),
  ).toEqual({ ids: [a, b], limit: 20 });
  const serving = core.portion({ quantityUnit: "g", servingSize: 30, per100: { kcal: 400, proteinG: 10 } });
  expect(serving).toMatchObject({ units: ["serving", "g"], defaultUnit: "serving", defaultQuantity: 1, needsKcal: false, canSave: true });
  expect(serving.preview?.kcal).toBe(120);
  expect(core.logEntry({ name: "Volkorenbrood", quantity: 35.04, unit: "g", per100: { kcal: 250, proteinG: 10 } })).toEqual({
    name: "Volkorenbrood",
    quantity: 35,
    nutrients: { kcal: 87.6, proteinG: 3.5 },
  });
  expect(core.logEntry({ name: "x", quantity: 2, unit: "serving", per100: { kcal: 250 } })).toBeNull();
  expect(core.ownProduct({ name: "x", brand: "", gtin: "", isMillilitre: false, kcal: 950 })).toEqual({});
  expect(core.dayTotals({ entries: [{ kcal: 100, proteinG: 5 }, { kcal: 50.5 }] })).toMatchObject({ kcal: 150.5, unknownProtein: 1, unknownFat: 2 });
});

test("the partner as the engine sees it today", async () => {
  const core = await loadCore(wasm);
  const target = { kcal: 2000, proteinG: 120, carbsG: 250, fatG: 70 };
  const snapshot = core.partnerSnapshot({
    creature: { species: "owl", colorIndex: 0, tone: "sweet", createdOn: "2026-11-14", bodyShape: 0.3, xp: 0, offTargetDays: 0 },
    entries: ["2026-11-21", "2026-11-22", "2026-11-23"].map((day) => ({ day, kcal: 2000, proteinG: 120 })),
    workoutDays: [],
    periods: [],
    fallback: target,
    today: "2026-11-24",
  });
  expect(snapshot.historyDays).toBe(8);
  expect(["happy", "content", "sluggish", "tired", "hungry", "asleep"]).toContain(snapshot.mood);
  expect(snapshot.energy).toBeGreaterThanOrEqual(0);
  expect(snapshot.energy).toBeLessThanOrEqual(1);
});
