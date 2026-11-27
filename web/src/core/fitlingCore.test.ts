import { readFile } from "node:fs/promises";
import { expect, test, vi } from "vitest";
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

/**
 * A stand-in for the rules, written out by hand, that answers every call with {} and traps when it is in a bad state,
 * as Swift does after a fatal error. A call to macros puts it in that state, like an earlier call that left something
 * broken behind; a call to kcalShares recurses until the stack runs out. In text form:
 *   (func $deep (call $deep))
 *   (func $call (param i32 i32) (result i64)
 *     (if (i32.eq (i32.load8_u offset=7 (local.get 0)) (i32.const 0x6b)) (then (call $deep)))   ;; {"fn":"k...
 *     (if (i32.eq (i32.load8_u offset=7 (local.get 0)) (i32.const 0x6d))                        ;; {"fn":"m...
 *       (then (global.set 0 (i32.const 1)) (return (i64.const answer))))
 *     (if (global.get 0) (then unreachable))
 *     (i64.const answer))
 */
function rulesThatBreak(): ArrayBuffer {
  const unsigned = (value: number) => {
    const out: number[] = [];
    do {
      const low = value & 0x7f;
      value >>>= 7;
      out.push(value ? low | 0x80 : low);
    } while (value);
    return out;
  };
  const signed = (value: bigint) => {
    const out: number[] = [];
    for (;;) {
      const low = Number(value & 0x7fn);
      value >>= 7n;
      const done = (value === 0n && (low & 0x40) === 0) || (value === -1n && (low & 0x40) !== 0);
      out.push(done ? low : low | 0x80);
      if (done) return out;
    }
  };
  const section = (id: number, content: number[]) => [id, ...unsigned(content.length), ...content];
  const vector = (items: number[][]) => [...unsigned(items.length), ...items.flat()];
  const name = (text: string) => [...unsigned(text.length), ...new TextEncoder().encode(text)];
  const body = (code: number[]) => [...unsigned(code.length + 1), 0, ...code];
  // The answer "{}" at address 2048: its address in the upper 32 bits, its length in the lower 32.
  const answer = signed((2048n << 32n) | 2n);
  const call = [
    ...[0x20, 0, 0x2d, 0, 7, 0x41, ...signed(0x6bn), 0x46, 0x04, 0x40, 0x10, 4, 0x0b],
    ...[0x20, 0, 0x2d, 0, 7, 0x41, ...signed(0x6dn), 0x46, 0x04, 0x40],
    ...[0x41, 1, 0x24, 0, 0x42, ...answer, 0x0f, 0x0b],
    ...[0x23, 0, 0x04, 0x40, 0x00, 0x0b],
    ...[0x42, ...answer, 0x0b],
  ];
  const bytes = [
    ...[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00],
    ...section(1, vector([[0x60, 1, 0x7f, 1, 0x7f], [0x60, 2, 0x7f, 0x7f, 0], [0x60, 2, 0x7f, 0x7f, 1, 0x7e], [0x60, 0, 0]])),
    ...section(3, vector([[0], [1], [2], [3], [3]])),
    ...section(5, vector([[0x00, 1]])),
    ...section(6, vector([[0x7f, 1, 0x41, 0, 0x0b]])),
    ...section(
      7,
      vector([
        [...name("memory"), 0x02, 0],
        [...name("fitling_alloc"), 0x00, 0],
        [...name("fitling_free"), 0x00, 1],
        [...name("fitling_call"), 0x00, 2],
        [...name("_initialize"), 0x00, 3],
      ]),
    ),
    ...section(10, vector([body([0x41, ...signed(1024n), 0x0b]), body([0x0b]), body(call), body([0x0b]), body([0x10, 4, 0x0b])])),
    ...section(11, vector([[0x00, 0x41, ...signed(2048n), 0x0b, ...name("{}")]])),
  ];
  return new Uint8Array(bytes).buffer;
}

// UNFORGET S51: a trap leaves the module in an unknown state (its stack, a value half made). The call that trapped is
// an error the app can show; the module is replaced, so the calls after it are answered again.
test("after a trap a fresh copy of the rules answers", async () => {
  const told = vi.spyOn(console, "error").mockImplementation(() => undefined);
  try {
    const core = await loadCore(rulesThatBreak());
    expect(core.macros({ kcal: 2000, weightKg: 80, goal: "maintain" })).toEqual({});
    expect(() => core.dailyPlan(maintain)).toThrow("error.server");
    expect(told).toHaveBeenCalledWith(expect.stringContaining("fitling-core dailyPlan"));
    await vi.waitFor(() => expect(core.dailyPlan(maintain)).toEqual({}));
    // A stack that runs out stops the module halfway too.
    expect(() => core.kcalShares({ kcal: 2000, proteinG: 100, carbsG: 250, fatG: 70 })).toThrow("error.server");
    expect(told).toHaveBeenCalledWith(expect.stringContaining("fitling-core kcalShares"));
    await vi.waitFor(() => expect(core.dailyPlan(maintain)).toEqual({}));
  } finally {
    told.mockRestore();
  }
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
  expect(core.searchKey({ text: "  Crème Brûlée " })).toEqual({ key: "creme brulee", pattern: "creme brulee" });
  expect(core.searchKey({ text: "50% *x*" }).pattern).toBe("50% \\*x\\*");
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

test("the partner folded, dressed and today's XP (web phase 3)", async () => {
  const core = await loadCore(wasm);
  const creature = { species: "owl", colorIndex: 0, tone: "sweet", createdOn: "2026-11-14", bodyShape: 0.3, xp: 80, offTargetDays: 0 };
  const days = {
    creature,
    entries: ["2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23"].map((day) => ({ day, kcal: 2000, proteinG: 130 })),
    workoutDays: [],
    periods: [],
    fallback: { kcal: 2000, proteinG: 120, carbsG: 250, fatG: 70 },
    today: "2026-11-24",
  };
  const once = core.partnerAdvance(days);
  expect(once.changed).toBe(true);
  expect(once.creature.lastProcessedDay).toBe("2026-11-23");
  expect(core.partnerAdvance({ ...days, creature: once.creature })).toMatchObject({ changed: false, events: [] });
  expect(core.advanceFrom({ creature: { ...creature, lastProcessedDay: "2026-11-20" } })).toEqual({ firstDay: "2026-11-14" });
  expect(core.wearing({ worn: ["scarf", "crown"], item: "cap", unlocked: ["scarf", "cap", "crown"] })).toEqual({ worn: ["scarf", "cap"] });
  const snapshot = core.partnerSnapshot({ ...days, creature: once.creature });
  expect(snapshot.lockedColorLevels.length).toBeGreaterThan(0);
  expect(snapshot.items.map((entry) => entry.item)).toEqual(["scarf", "cap", "bow", "glasses", "backpack", "crown"]);
  expect(snapshot.items.find((entry) => entry.item === "crown")?.unlockLevel).toBe(15);
  expect(Object.keys(snapshot.todayXP).sort()).toEqual(["logging", "protein", "withinTarget", "workout"]);
});

test("training from the same TrainingRecords as the iPhone (web phase 4)", async () => {
  const core = await loadCore(wasm);
  const squat = {
    id: "00000000-0000-4000-8000-000000000001",
    name: { nl: "Squat" },
    kind: "compound",
    loadType: "external",
    primaryMuscles: ["quads"],
    secondaryMuscles: [],
    defaultStepKg: 2.5,
  };
  const program = { id: "00000000-0000-4000-8000-000000000002", name: { nl: "Volledig lichaam" }, daysPerWeek: 2, deleted: false };
  const days = [0, 1].map((position) => ({
    id: `00000000-0000-4000-8000-00000000001${position}`,
    programID: program.id,
    name: { nl: `Dag ${position + 1}` },
    position,
    updatedAt: 0,
    deleted: false,
  }));
  const items = days.map((day, index) => ({
    id: `00000000-0000-4000-8000-00000000002${index}`,
    programDayID: day.id,
    exerciseID: squat.id,
    position: 0,
    targetSets: 3,
    repMin: 6,
    repMax: 8,
    restSeconds: 150,
  }));
  const done = { id: "00000000-0000-4000-8000-000000000030", programDayID: days[0].id, performedOn: "2026-11-15", startedAt: 1_794_740_000, endedAt: 1_794_743_600 };
  const now = { id: "00000000-0000-4000-8000-000000000031", programDayID: days[1].id, performedOn: "2026-11-18", startedAt: 1_795_000_000 };
  const sets = [0, 1, 2].map((position) => ({
    id: `00000000-0000-4000-8000-00000000004${position}`,
    sessionID: done.id,
    exerciseID: squat.id,
    position,
    weightKg: 100,
    reps: 6,
    rpe: 7,
    isWarmup: false,
  }));
  const training = {
    userID: "00000000-0000-4000-8000-0000000000ff",
    today: "2026-11-18",
    languages: ["nl"],
    exercises: [squat],
    programs: [program],
    days,
    items,
    settings: [],
    sessions: [done, now],
    sets,
  };
  const overview = core.trainingOverview({ training });
  expect(overview.active?.id).toBe(now.id);
  expect(overview.recent[0]).toMatchObject({ id: done.id, title: "Dag 1", setCount: 3 });
  const workout = core.workout({ training, sessionID: now.id, added: [], usesPounds: false });
  expect(workout.entries[0]).toMatchObject({ exerciseID: squat.id, restSeconds: 150, draft: { weight: 100, reps: 7 } });
  expect(core.loggedSet({ weight: 135, reps: 5, usesPounds: true })).toMatchObject({ canLog: true, weightKg: 61.23 });
  expect(core.trainingChoices().durations).toContain(60);
  expect(core.measurementStored({ value: 176, kind: "weight", usesMetric: false }).value).toBe(79.8);
});

test("the week menu from the same MenuBook as the iPhone (web phase 5)", async () => {
  const core = await loadCore(wasm);
  const recipes = ["breakfast", "lunch", "dinner"].flatMap((slot, group) =>
    [1, 2, 3].map((number) => ({
      id: `00000000-0000-4000-8000-0000000001${group}${number}`,
      title: { nl: `${slot} ${number}` },
      servings: 2,
      cookMinutes: 20,
      kcalPerServing: 700,
      proteinGPerServing: 35,
      carbsGPerServing: 70,
      fatGPerServing: 20,
      keepsWell: false,
      mealSlots: [slot],
      tags: [],
      productIDs: [],
    })),
  );
  const menu = {
    userID: "00000000-0000-4000-8000-0000000000ff",
    today: "2026-11-18",
    languages: ["nl"],
    recipes,
    removedRecipes: [],
    entries: [],
    settings: { excludedTags: [], mealPrep: false, mealSlots: ["breakfast", "lunch", "dinner"] },
    excludedProductIDs: [],
  };
  const change = core.menuGenerate({ menu, days: 3, seed: "42", targets: { kcal: 2200, proteinG: 120, carbsG: 250, fatG: 70 } });
  expect(change.removed).toEqual([]);
  expect(change.added).toHaveLength(9);
  expect(new Set(change.added.map((meal) => meal.day))).toEqual(new Set(["2026-11-18", "2026-11-19", "2026-11-20"]));
  expect(core.ownRecipeComplete({ title: "Soep", servings: 2, cookMinutes: 30, kcal: 300, protein: 12, carbs: 30, fat: 10, mealSlots: ["lunch"] }).complete).toBe(true);
  expect(core.storedIngredientQuantity({ quantity: 250.004 })).toEqual({ quantity: 250 });
  expect(core.storedIngredientQuantity({ quantity: 0.004 })).toEqual({});
});

test("the shopping list from the same ShoppingBook as the iPhone (web phase 6)", async () => {
  const core = await loadCore(wasm);
  const overview = core.shoppingOverview({
    shopping: {
      today: "2026-11-18",
      items: [
        { id: "00000000-0000-4000-8000-000000000001", name: "Melk", aisle: "dairy", isChecked: false, source: "manual" },
        { id: "00000000-0000-4000-8000-000000000002", name: "Appels", aisle: "produce", isChecked: false, source: "manual" },
      ],
      offers: [],
      supermarkets: [],
      favoriteSupermarketIDs: [],
      confirmedOfferIDs: [],
    },
  });
  expect(overview.items.map((item) => item.name)).toEqual(["Appels", "Melk"]);
  expect(core.shoppingNewItem({ text: "   " }).item).toBeUndefined();
});
