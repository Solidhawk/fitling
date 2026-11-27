import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "./fixtures";
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

// The exercises did not reach the server. Back to the list and the original again: copying finishes the same copy,
// with all its days and exercises, instead of making a second one (UNFORGET S54).
test("copyingAgainAfterAFailureMakesOneCopy", async ({ page }) => {
  const programme = await firstProgramme();
  const user = await openTraining(page);
  await page.getByTestId(`training.program.${programme.id}`).click();
  let failures = 1;
  await page.route("**/rest/v1/program_exercises*", async (route) => {
    if (route.request().method() === "POST" && failures-- > 0) {
      return route.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ message: "unavailable" }) });
    }
    return route.continue();
  });
  await page.getByRole("button", { name: nl("training.program.copy") }).click();
  await page.getByRole("alertdialog").getByRole("button").click();
  await page.getByRole("button", { name: nl("training.title"), exact: true }).click();
  await page.getByTestId(`training.program.${programme.id}`).click();
  await page.getByRole("button", { name: nl("training.program.copy") }).click();
  const copyName = nl("training.program.copyName %@").replace("%@", programme.name);
  await expect(page.getByRole("heading", { name: copyName })).toBeVisible({ timeout: 15_000 });
  const { data } = await admin.from("programs").select("id").eq("owner_id", user.id);
  expect(data).toHaveLength(1);
  const { data: days } = await admin.from("program_days").select("id").eq("program_id", data![0].id);
  expect(days).toHaveLength(programme.days.length);
  const { count: copied } = await admin
    .from("program_exercises")
    .select("id", { count: "exact", head: true })
    .in("program_day_id", days!.map((day) => day.id));
  const { count: original } = await admin
    .from("program_exercises")
    .select("id", { count: "exact", head: true })
    .in("program_day_id", programme.days.map((day) => day.id))
    .is("deleted_at", null);
  expect(copied).toBe(original);
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

/** A programme of the user's own, made on this screen and open. */
async function ownProgramme(page: Page, name: string) {
  await page.getByTestId("training.program.new").click();
  await page.getByTestId("training.program.name").fill(name);
  await page.getByRole("button", { name: nl("common.save") }).click();
  await expect(page.getByRole("heading", { name })).toBeVisible({ timeout: 15_000 });
}

// A delete the server turns down keeps the programme open with its error: going back anyway took the alert away with
// the screen it lived in (UNFORGET S42). Trying again removes it.
test("aFailedDeleteKeepsTheProgrammeWithItsError", async ({ page }) => {
  const user = await openTraining(page);
  await ownProgramme(page, "Benen");
  let failures = 1;
  await page.route("**/rest/v1/programs*", (route) =>
    route.request().method() === "PATCH" && failures-- > 0
      ? route.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ message: "unavailable" }) })
      : route.continue(),
  );
  const remove = async () => {
    await page.getByTestId("program.options").click();
    await page.getByRole("menuitem", { name: nl("training.program.delete") }).click();
    await page.getByRole("button", { name: nl("training.program.delete") }).click();
  };
  await remove();
  await expect(page.getByRole("alertdialog", { name: nl("error.server") })).toBeVisible();
  await page.getByRole("alertdialog").getByRole("button").click();
  await expect(page.getByRole("heading", { name: "Benen" })).toBeVisible();
  await remove();
  await expect(page.getByTestId("training.compose")).toBeVisible({ timeout: 15_000 });
  const { data } = await admin.from("programs").select("deleted_at").eq("owner_id", user.id);
  expect(data?.map((program) => program.deleted_at !== null)).toEqual([true]);
});

// Removed on another device while it is open here: once read back, the screen goes back to the list instead of
// offering a programme that no longer exists (UNFORGET S42).
test("aProgrammeRemovedOnAnotherDeviceCloses", async ({ page }) => {
  const user = await openTraining(page);
  await ownProgramme(page, "Armen");
  const stamp = new Date().toISOString();
  const removed = await admin.from("programs").update({ deleted_at: stamp, updated_at: stamp }).eq("owner_id", user.id);
  if (removed.error) throw removed.error;
  await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
  await expect(page.getByTestId("training.compose")).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole("heading", { name: "Armen" })).toHaveCount(0);
});

// Screens left open on another tab lead nowhere: one Back from a programme goes to the training list and on past the
// menu's screens, which are no longer on screen (UNFORGET S40).
test("backPassesTheScreensOfAnotherTab", async ({ page }) => {
  const programme = await firstProgramme();
  await openTraining(page);
  await page.getByRole("tab", { name: nl("menu.title") }).click();
  await page.getByTestId("menu.recipes").click();
  await expect(page.getByTestId("menu.recipe.new")).toBeVisible({ timeout: 15_000 });
  await page.getByRole("tab", { name: nl("training.title") }).click();
  await page.getByTestId(`training.program.${programme.id}`).click();
  await expect(page.getByRole("heading", { name: programme.name })).toBeVisible();
  await page.goBack();
  await expect(page.getByTestId("training.compose")).toBeVisible();
  await expect.poll(() => page.evaluate(() => history.state)).toBeNull();
});

// A screen opens at the top, also when another screen at the same depth was scrolled before it: back from a deeper
// screen it returns to its own place, not to the other one's (review of PR #62).
test("backReturnsToTheScreensOwnPlace", async ({ page }) => {
  const programs = await admin.from("programs").select("id").is("owner_id", null).is("deleted_at", null).order("id").limit(2);
  if (programs.error) throw programs.error;
  const [first, second] = programs.data!.map((program) => program.id as string);
  await openTraining(page);
  await page.getByTestId(`training.program.${first}`).click();
  await expect(page.locator('[data-page="program"]')).toBeVisible();
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  expect(await page.evaluate(() => window.scrollY)).toBeGreaterThan(100);
  await page.goBack();
  await page.getByTestId(`training.program.${second}`).click();
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
  await page.locator('[data-testid^="program.exercise."]').first().click();
  await expect(page.locator('[data-page="exerciseProgress"]')).toBeVisible();
  await page.goBack();
  await expect(page.locator('[data-page="program"]')).toBeVisible();
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
});

// The menu of a programme opens over everything: a tap on a tab while it is open closes the menu, it does not switch
// tabs (review of PR #62).
test("theProgrammeMenuCoversTheTabBar", async ({ page }) => {
  await openTraining(page);
  await ownProgramme(page, "Benen en billen");
  await page.getByTestId("program.options").click();
  await expect(page.getByRole("menuitem", { name: nl("training.program.rename") })).toBeVisible();
  const tab = await page.getByRole("tab", { name: nl("menu.title") }).boundingBox();
  const covered = await page.evaluate(
    ({ x, y }) => document.elementFromPoint(x, y)?.closest(".tab-bar-frame") === null,
    { x: tab!.x + tab!.width / 2, y: tab!.y + tab!.height / 2 },
  );
  expect(covered).toBe(true);
});
