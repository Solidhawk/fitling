import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "./fixtures";
import { exercise, finishedWorkout, firstProgramme, openTraining } from "./training";
import { admin, nl, nlCount } from "./users";

// TrainingTests and ComposedTrainingTests on iOS: the training tab and its programmes (web phase 4).

test("theNextWorkoutIsOffered", async ({ page }, info) => {
  const programme = await firstProgramme();
  const squat = await exercise("Barbell back squat");
  await openTraining(page, (userID) => finishedWorkout(userID, squat.id, 2, [[60, 8]], programme.days[0].id).then(() => undefined));
  await expect(page.getByTestId("training.next")).toContainText(programme.days[1].name);
  await expect(page.getByTestId("training.next")).toContainText(programme.name);
  await expect(page.getByTestId("training.recent").first()).toContainText(programme.days[0].name);
  await page.screenshot({ path: `test-results/screens/${info.project.name}-training.png`, fullPage: true });
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => violation.id)).toEqual([]);
});

test("sharedProgramsCannotBeChanged", async ({ page }, info) => {
  const programme = await firstProgramme();
  const user = await openTraining(page);
  await page.getByTestId(`training.program.${programme.id}`).click();
  await expect(page.getByRole("heading", { name: programme.name })).toBeVisible();
  await expect(page.getByText(nl("training.program.addExercise"))).toHaveCount(0);
  await page.screenshot({ path: `test-results/screens/${info.project.name}-schema.png`, fullPage: true });
  // Copying makes it the user's own, with the same days, to change.
  await page.getByRole("button", { name: nl("training.program.copy") }).click();
  const copyName = nl("training.program.copyName %@").replace("%@", programme.name);
  await expect(page.getByRole("heading", { name: copyName })).toBeVisible({ timeout: 15_000 });
  await expect(page.getByText(nl("training.program.addExercise")).first()).toBeVisible();
  const { data } = await admin.from("programs").select("id").eq("owner_id", user.id);
  expect(data).toHaveLength(1);
});

// A double tap on Kopiëren makes one copy, not two (UNFORGET S42).
test("aDoubleTapOnCopyMakesOneCopy", async ({ page }) => {
  const programme = await firstProgramme();
  const user = await openTraining(page);
  await page.getByTestId(`training.program.${programme.id}`).click();
  await page.getByRole("button", { name: nl("training.program.copy") }).dblclick();
  const copyName = nl("training.program.copyName %@").replace("%@", programme.name);
  await expect(page.getByRole("heading", { name: copyName })).toBeVisible({ timeout: 15_000 });
  await page.waitForTimeout(1500);
  const { data } = await admin.from("programs").select("id").eq("owner_id", user.id);
  expect(data).toHaveLength(1);
});

// The days did not reach the server: copying again makes one copy, with all its days (UNFORGET S54).
test("copyingAgainAfterAFailureMakesOneCopy", async ({ page }) => {
  const programme = await firstProgramme();
  const user = await openTraining(page);
  await page.getByTestId(`training.program.${programme.id}`).click();
  let failures = 1;
  await page.route("**/rest/v1/program_days*", async (route) => {
    if (route.request().method() === "POST" && failures-- > 0) {
      return route.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ message: "unavailable" }) });
    }
    return route.continue();
  });
  await page.getByRole("button", { name: nl("training.program.copy") }).click();
  await page.getByRole("alertdialog").getByRole("button").click();
  await page.getByRole("button", { name: nl("training.program.copy") }).click();
  const copyName = nl("training.program.copyName %@").replace("%@", programme.name);
  await expect(page.getByRole("heading", { name: copyName })).toBeVisible({ timeout: 15_000 });
  const { data } = await admin.from("programs").select("id").eq("owner_id", user.id);
  expect(data).toHaveLength(1);
  const { data: days } = await admin.from("program_days").select("id").eq("program_id", data![0].id);
  expect(days).toHaveLength(programme.days.length);
});

test("aNewProgramHasItsDays", async ({ page }) => {
  await openTraining(page);
  await page.getByTestId("training.program.new").click();
  await page.getByTestId("training.program.name").fill("Push en pull");
  await page.getByTestId("training.program.days").getByRole("button", { name: nl("common.decrease") }).click();
  await expect(page.getByTestId("training.program.days")).toContainText(nlCount("training.program.days %lld", 2));
  await page.getByRole("button", { name: nl("common.save") }).click();
  await expect(page.getByRole("heading", { name: "Push en pull" })).toBeVisible({ timeout: 15_000 });
  await expect(page.getByText(nl("training.day.default %lld").replace("%lld", "1"))).toBeVisible();
  await expect(page.getByText(nl("training.day.default %lld").replace("%lld", "2"))).toBeVisible();
});

test("exercisesAreAddedToADay", async ({ page }, info) => {
  const bench = await exercise("Bench press");
  await openTraining(page);
  await page.getByTestId("training.program.new").click();
  await page.getByTestId("training.program.name").fill("Borst");
  await page.getByRole("button", { name: nl("common.save") }).click();
  await expect(page.getByRole("heading", { name: "Borst" })).toBeVisible({ timeout: 15_000 });
  await page.getByText(nl("training.program.addExercise")).first().click();
  await page.getByTestId("picker.search").fill(bench.name);
  await page.screenshot({ path: `test-results/screens/${info.project.name}-oefening-kiezen.png` });
  await page.getByTestId(`picker.exercise.${bench.id}`).click();
  await expect(page.getByTestId("picker.sets")).toContainText(nl("training.picker.sets %lld").replace("%lld", "3"));
  await page.getByRole("button", { name: nl("common.save") }).click();
  await expect(page.getByTestId(`program.exercise.${bench.id}`)).toContainText(
    nl("training.item.detail %lld %lld %lld %lld").replace("%1$lld", "3").replace("%2$lld", "8").replace("%3$lld", "12").replace("%4$lld", "120"),
  );
});

test("theCoachNamesWhatCanGoHeavier", async ({ page }) => {
  const bench = await exercise("Bench press");
  await openTraining(page, (userID) => finishedWorkout(userID, bench.id, 2, [[60, 12], [60, 12], [60, 12]]).then(() => undefined));
  const note = page.getByTestId(`training.coach.heavier.${bench.id}`);
  await expect(note).toContainText(bench.name);
  await expect(note).toContainText(/62,5\s?kg/);
});
