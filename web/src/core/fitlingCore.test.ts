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

test("an unknown goal is an error, not a crash", async () => {
  const core = await loadCore(wasm);
  expect(() => core.dailyPlan({ ...maintain, goal: "x" as DailyPlanInput["goal"] })).toThrow();
  // The module still answers after a failure.
  expect(core.dailyPlan(maintain).targets.kcal).toBe(2760);
});
