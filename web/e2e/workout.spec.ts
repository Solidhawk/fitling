import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "./fixtures";
import { exercise, finishedWorkout, firstProgramme, openTraining } from "./training";
import { admin, nl } from "./users";

// WorkoutTests and ProgressionAdviceTests on iOS: composing and logging a workout (web phase 4).

async function startFirstDay(page: Page) {
  const programme = await firstProgramme();
  await page.getByTestId(`training.program.${programme.id}`).click();
  await page.getByTestId(`training.start.${programme.days[0].id}`).click();
  await expect(page.getByRole("dialog", { name: programme.days[0].name })).toBeVisible({ timeout: 15_000 });
  return programme;
}

async function logSet(page: Page, exerciseID: string, weight: string, reps: string) {
  await page.getByTestId(`workout.weight.${exerciseID}`).fill(weight);
  await page.getByTestId(`workout.reps.${exerciseID}`).fill(reps);
  await page.getByTestId(`workout.log.${exerciseID}`).click();
}

test("aComposedWorkoutStartsAndIsLogged", async ({ page }, info) => {
  const user = await openTraining(page);
  await page.getByTestId("training.compose").click();
  await page.getByTestId("training.compose.focus.push").click();
  await page.screenshot({ path: `test-results/screens/${info.project.name}-samenstellen.png`, fullPage: true });
  const planned = page.locator('[data-testid^="training.compose.exercise."]');
  await expect(planned.first()).toBeVisible();
  const first = (await planned.first().getAttribute("data-testid"))!.replace("training.compose.exercise.", "");
  await page.getByTestId("training.compose.start").click();
  const workout = page.getByRole("dialog", { name: nl("training.focus.push") });
  await expect(workout).toBeVisible({ timeout: 15_000 });
  await logSet(page, first, "40", "10");
  await expect(workout.getByTestId("workout.set")).toHaveCount(1);
  await page.screenshot({ path: `test-results/screens/${info.project.name}-training-loggen.png`, fullPage: true });
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => violation.id)).toEqual([]);
  await page.getByTestId("workout.finish").click();
  const records = page.getByRole("alertdialog", { name: nl("training.records.title") });
  if (await records.isVisible().catch(() => false)) await records.getByRole("button", { name: nl("common.ok") }).click();
  await expect(workout).toBeHidden({ timeout: 15_000 });
  await expect(page.getByTestId("training.recent").first()).toContainText(nl("training.focus.push"));
  const { data } = await admin.from("workout_sessions").select("ended_at").eq("user_id", user.id);
  expect(data?.[0]?.ended_at).toBeTruthy();
});

test("aSetNeedsWeightAndReps", async ({ page }) => {
  await openTraining(page);
  await startFirstDay(page);
  const log = page.locator('[data-testid^="workout.log."]').first();
  const exerciseID = (await log.getAttribute("data-testid"))!.replace("workout.log.", "");
  await page.getByTestId(`workout.reps.${exerciseID}`).fill("");
  await expect(log).toBeDisabled();
  await page.getByTestId(`workout.reps.${exerciseID}`).fill("8");
  await page.getByTestId(`workout.weight.${exerciseID}`).fill("");
  await expect(log).toBeDisabled();
});

test("restTimerStartsAfterAWorkingSet", async ({ page }) => {
  await openTraining(page);
  await startFirstDay(page);
  const exerciseID = (await page.locator('[data-testid^="workout.log."]').first().getAttribute("data-testid"))!.replace("workout.log.", "");
  // A warm-up set does not start the rest.
  await page.getByRole("switch", { name: nl("training.set.warmup") }).first().check();
  await logSet(page, exerciseID, "20", "10");
  await expect(page.getByTestId("workout.set")).toHaveCount(1);
  await expect(page.getByTestId("workout.rest")).toHaveCount(0);
  await page.getByRole("switch", { name: nl("training.set.warmup") }).first().uncheck();
  await logSet(page, exerciseID, "40", "8");
  await expect(page.getByTestId("workout.rest")).toBeVisible();
  await expect(page.getByTestId("workout.rest")).toContainText(nl("training.rest.title"));
  await page.getByRole("button", { name: nl("training.rest.skip") }).click();
  await expect(page.getByTestId("workout.rest")).toHaveCount(0);
});

test("finishingShowsTheRecords", async ({ page }, info) => {
  const programme = await firstProgramme();
  const items = await admin.from("program_exercises").select("exercise_id").eq("program_day_id", programme.days[0].id).order("position");
  const exerciseID = items.data![0].exercise_id as string;
  await openTraining(page, (userID) => finishedWorkout(userID, exerciseID, 3, [[50, 8]], programme.days[0].id).then(() => undefined));
  await startFirstDay(page);
  await logSet(page, exerciseID, "55", "8");
  await expect(page.getByTestId("workout.set")).toHaveCount(1);
  await page.getByTestId("workout.finish").click();
  const records = page.getByRole("alertdialog", { name: nl("training.records.title") });
  await expect(records).toBeVisible({ timeout: 15_000 });
  await expect(records).toContainText(/55\s?kg/);
  await page.screenshot({ path: `test-results/screens/${info.project.name}-records.png` });
  await records.getByRole("button", { name: nl("common.ok") }).click();
  await expect(records).toBeHidden();
});

test("discardingRemovesTheWorkout", async ({ page }) => {
  const user = await openTraining(page);
  await startFirstDay(page);
  const exerciseID = (await page.locator('[data-testid^="workout.log."]').first().getAttribute("data-testid"))!.replace("workout.log.", "");
  await logSet(page, exerciseID, "40", "8");
  await expect(page.getByTestId("workout.set")).toHaveCount(1);
  await page.getByTestId("workout.options").click();
  await page.getByRole("menuitem", { name: nl("training.workout.discard") }).click();
  await page.getByRole("button", { name: nl("training.workout.discard") }).click();
  await expect(page.getByTestId("training.compose")).toBeVisible({ timeout: 15_000 });
  await expect(page.getByTestId("training.resume")).toHaveCount(0);
  const { data } = await admin.from("workout_sets").select("deleted_at").eq("user_id", user.id);
  expect(data?.every((set) => set.deleted_at !== null)).toBe(true);
});

// Review Focus: a workout open on two devices shows the sets logged on the other one, with their exercise.
test("setsFromAnotherDeviceAreShown", async ({ page }) => {
  const curl = await exercise("Dumbbell curl");
  const user = await openTraining(page);
  await startFirstDay(page);
  await page.getByTestId("workout.options").click();
  await page.getByRole("menuitem", { name: nl("training.workout.later") }).click();
  await expect(page.getByTestId("training.resume")).toBeVisible({ timeout: 15_000 });
  const session = await admin.from("workout_sessions").select("id").eq("user_id", user.id).is("ended_at", null).single();
  const stored = await admin.from("workout_sets").insert({
    id: crypto.randomUUID(),
    user_id: user.id,
    session_id: session.data!.id,
    exercise_id: curl.id,
    position: 0,
    weight_kg: 12,
    reps: 10,
    is_warmup: false,
    updated_at: new Date().toISOString(),
  });
  if (stored.error) throw stored.error;
  await page.reload();
  await page.getByRole("tab", { name: nl("training.title") }).click();
  await page.getByTestId("training.resume").click();
  await expect(page.getByTestId(`workout.exercise.${curl.id}`)).toBeVisible({ timeout: 15_000 });
  await expect(page.getByTestId("workout.set")).toHaveCount(1);
});
