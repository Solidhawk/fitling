import { expect, test } from "./fixtures";
import { daysBefore, exercise, finishedWorkout, openTraining, png, tapRow } from "./training";
import { admin, nl } from "./users";

// The progress screens of the training tab, the body log and the progress photos (web phase 4).

test("progressShowsEveryWorkout", async ({ page }, info) => {
  const bench = await exercise("Bench press");
  await openTraining(page, async (userID) => {
    await finishedWorkout(userID, bench.id, 9, [[60, 8], [60, 8]]);
    await finishedWorkout(userID, bench.id, 2, [[62.5, 8], [62.5, 8]]);
  });
  await tapRow(page, nl("training.progress.exercises"));
  await page.getByTestId(`progress.exercise.${bench.id}`).click();
  await expect(page.getByRole("heading", { name: bench.name })).toBeVisible();
  await expect(page.getByTestId("progress.workouts")).toHaveText("2");
  await expect(page.getByRole("img", { name: nl("training.chart.oneRepMax") })).toBeVisible();
  await page.screenshot({ path: `test-results/screens/${info.project.name}-oefening.png`, fullPage: true });
});

test("theStepIsSaved", async ({ page }) => {
  const bench = await exercise("Bench press");
  const user = await openTraining(page, (userID) => finishedWorkout(userID, bench.id, 2, [[60, 8]]).then(() => undefined));
  await tapRow(page, nl("training.progress.exercises"));
  await page.getByTestId(`progress.exercise.${bench.id}`).click();
  // Quick taps are stored one after the other: one setting, with the last step (bug-echo of the menu preferences).
  const increase = page.getByTestId("progress.step").getByRole("button", { name: nl("common.increase") });
  await Promise.all([increase.click(), increase.click(), increase.click()]);
  await expect(page.getByTestId("progress.step")).toContainText(/3,25\s?kg/);
  await expect
    .poll(async () => (await admin.from("exercise_settings").select("step_kg").eq("user_id", user.id).eq("exercise_id", bench.id)).data?.map((row) => Number(row.step_kg)))
    .toEqual([3.25]);
});

test("volumeCountsTheWeek", async ({ page }, info) => {
  const bench = await exercise("Bench press");
  await openTraining(page, (userID) => finishedWorkout(userID, bench.id, 0, [[60, 8], [60, 8], [60, 8]]).then(() => undefined));
  await page.getByRole("button", { name: nl("training.progress.volume") }).click();
  await expect(page.getByTestId("volume.chart")).toContainText(nl("muscle.chest"));
  await expect(page.getByTestId("volume.chart")).toContainText("3");
  await page.screenshot({ path: `test-results/screens/${info.project.name}-volume.png`, fullPage: true });
  await page.getByRole("radio", { name: nl("training.volume.lastWeek") }).click();
  await expect(page.getByTestId("volume.chart")).toContainText(nl("training.volume.empty"));
});

test("measurementsAreAddedAndShown", async ({ page }, info) => {
  const user = await openTraining(page);
  await page.getByRole("button", { name: nl("body.title") }).click();
  await page.getByTestId("body.value").fill("80,4");
  await page.getByRole("button", { name: nl("body.add") }).click();
  await expect(page.getByTestId("body.measurement")).toContainText(/80,4\s?kg/);
  await page.screenshot({ path: `test-results/screens/${info.project.name}-lichaam.png`, fullPage: true });
  const { data } = await admin.from("body_measurements").select("kind, value").eq("user_id", user.id);
  expect(data).toEqual([{ kind: "weight", value: 80.4 }]);
});

test.describe("around midnight in Tokyo", () => {
  test.use({ timezoneId: "Asia/Tokyo" });

  // Lichaam open since the evening: a measurement added after midnight is for the new day, not the day the screen
  // opened on (UNFORGET S53). Yesterday in Tokyo, so the fake clock is never ahead of the real one.
  test("aMeasurementAfterMidnightIsForTheNewDay", async ({ page }) => {
    const day = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Tokyo" }).format(new Date(Date.now() - 86_400_000));
    const [year, month, date] = day.split("-").map(Number);
    const next = new Date(Date.UTC(year, month - 1, date + 1)).toISOString().slice(0, 10);
    await page.clock.setFixedTime(new Date(`${day}T23:59:00+09:00`));
    const user = await openTraining(page);
    await page.getByRole("button", { name: nl("body.title") }).click();
    await expect(page.getByTestId("body.value")).toBeVisible();
    await page.clock.setFixedTime(new Date(`${next}T00:01:00+09:00`));
    await page.getByTestId("body.value").fill("80,4");
    await page.getByRole("button", { name: nl("body.add") }).click();
    await expect(page.getByTestId("body.measurement")).toContainText(/80,4\s?kg/);
    const { data } = await admin.from("body_measurements").select("measured_on").eq("user_id", user.id);
    expect(data).toEqual([{ measured_on: next }]);
  });
});

// The date field emptied by hand: the measurement is for today, not refused; a day picked earlier stays (UNFORGET S42,
// S53).
test("anEmptyDateFieldMeansTodayAndAPickedDayStays", async ({ page }) => {
  const user = await openTraining(page);
  await page.getByRole("button", { name: nl("body.title") }).click();
  const field = page.getByLabel(nl("body.date"));
  await page.getByTestId("body.value").fill("80,4");
  await field.fill("");
  await page.getByRole("button", { name: nl("body.add") }).click();
  await expect(page.getByTestId("body.measurement")).toContainText(/80,4\s?kg/);
  await page.getByTestId("body.value").fill("80,9");
  await field.fill(daysBefore(1));
  await page.getByRole("button", { name: nl("body.add") }).click();
  await expect(page.getByTestId("body.measurement")).toHaveCount(2, { timeout: 15_000 });
  const { data } = await admin.from("body_measurements").select("measured_on, value").eq("user_id", user.id).order("measured_on");
  expect(data).toEqual([
    { measured_on: daysBefore(1), value: 80.9 },
    { measured_on: daysBefore(0), value: 80.4 },
  ]);
});

// A double tap stores one measurement, not two (UNFORGET S42).
test("aDoubleTapAddsOneMeasurement", async ({ page }) => {
  const user = await openTraining(page);
  await page.getByRole("button", { name: nl("body.title") }).click();
  await page.getByTestId("body.value").fill("80,4");
  await page.getByRole("button", { name: nl("body.add") }).dblclick();
  await expect(page.getByTestId("body.measurement")).toContainText(/80,4\s?kg/);
  // Room for a second write to land before counting.
  await page.waitForTimeout(1500);
  const { data } = await admin.from("body_measurements").select("value").eq("user_id", user.id);
  expect(data).toEqual([{ value: 80.4 }]);
});

test("photosStayOnThisDevice", async ({ page }, info) => {
  await openTraining(page);
  const uploads: string[] = [];
  page.on("request", (request) => {
    if (request.method() !== "GET" && /storage|photo/i.test(request.url())) uploads.push(request.url());
  });
  await page.getByRole("button", { name: nl("photos.title") }).click();
  await expect(page.getByText(nl("photos.empty"))).toBeVisible();
  await page.getByTestId("photos.picker").setInputFiles({ name: "voortgang.png", mimeType: "image/png", buffer: png() });
  await expect(page.getByTestId("photos.tile")).toHaveCount(1);
  await page.screenshot({ path: `test-results/screens/${info.project.name}-fotos.png` });
  expect(uploads).toEqual([]);
  await page.getByTestId("photos.tile").click();
  await page.getByRole("button", { name: nl("photos.delete") }).click();
  await page.getByRole("button", { name: nl("photos.delete") }).last().click();
  await expect(page.getByTestId("photos.tile")).toHaveCount(0);
});

test("animationStandsStillWithReduceMotion", async ({ page }) => {
  const bench = await exercise("Bench press");
  await openTraining(page, (userID) => finishedWorkout(userID, bench.id, 2, [[60, 8]]).then(() => undefined));
  await tapRow(page, nl("training.progress.exercises"));
  await page.getByTestId(`progress.exercise.${bench.id}`).click();
  await expect(page.getByTestId("exercise.animation")).toBeVisible();
  await page.getByTestId("exercise.animation").click();
  await expect(page.getByRole("button", { name: nl("training.animation.play") })).toBeVisible();
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.reload();
  await page.getByRole("tab", { name: nl("training.title") }).click();
  await tapRow(page, nl("training.progress.exercises"));
  await page.getByTestId(`progress.exercise.${bench.id}`).click();
  await expect(page.getByTestId("exercise.animation.still")).toBeVisible();
});

// An exercise that is gone once read back (removed from the catalogue, or an own one removed elsewhere) leaves its
// screen with only the way back, instead of the error screen of the whole app (UNFORGET S42).
test("anExerciseGoneWhileOpenLeavesTheWayBack", async ({ page }) => {
  const id = crypto.randomUUID();
  await openTraining(page, async (userID) => {
    const stored = await admin.from("exercises").insert({
      id,
      owner_id: userID,
      name: { nl: "Eigen oefening" },
      kind: "isolation",
      load_type: "external",
      equipment: "dumbbell",
      primary_muscles: ["biceps"],
      default_step_kg: 1,
      updated_at: new Date().toISOString(),
    });
    if (stored.error) throw stored.error;
    await finishedWorkout(userID, id, 2, [[12, 10]]);
  });
  await tapRow(page, nl("training.progress.exercises"));
  await page.getByTestId(`progress.exercise.${id}`).click();
  await expect(page.getByRole("heading", { name: "Eigen oefening" })).toBeVisible();
  const stamp = new Date().toISOString();
  const removed = await admin.from("exercises").update({ deleted_at: stamp, updated_at: stamp }).eq("id", id);
  if (removed.error) throw removed.error;
  await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
  await expect(page.getByRole("heading", { name: "Eigen oefening" })).toHaveCount(0);
  await expect(page.locator('[data-screen="failed"]')).toHaveCount(0);
  await page.locator('[data-page="exerciseProgress"] .nav-back').click();
  await expect(page.getByRole("heading", { name: nl("training.progress.exercises") })).toBeVisible();
});

// Switching the kind while the first one is still being read shows the kind picked last: the older answer that comes
// in later is dropped, instead of weights under "Taille" (UNFORGET S42).
test("theKindPickedLastIsShown", async ({ page }) => {
  await openTraining(page, async (userID) => {
    const stamp = new Date().toISOString();
    const stored = await admin.from("body_measurements").insert([
      { user_id: userID, measured_on: daysBefore(1), kind: "weight", value: 80, updated_at: stamp },
      { user_id: userID, measured_on: daysBefore(1), kind: "waist", value: 90, updated_at: stamp },
    ]);
    if (stored.error) throw stored.error;
  });
  let release = () => {};
  const held = new Promise<void>((resolve) => {
    release = resolve;
  });
  let first = true;
  await page.route("**/rest/v1/body_measurements*", async (route) => {
    if (route.request().method() === "GET" && first) {
      first = false;
      await held;
    }
    return route.continue();
  });
  await page.getByRole("button", { name: nl("body.title") }).click();
  await page.getByLabel(nl("body.kind")).selectOption("waist");
  await expect(page.getByTestId("body.measurement")).toContainText(/90\s?cm/);
  release();
  // Room for the held answer to arrive before looking again.
  await page.waitForTimeout(1500);
  await expect(page.getByTestId("body.measurement")).toHaveCount(1);
  await expect(page.getByTestId("body.measurement")).toContainText(/90\s?cm/);
});

// A photo lives only in this browser: adding one asks it to keep the storage when space runs low, also in a tab and
// not only on the home screen (UNFORGET S42).
test("addingAPhotoAsksToKeepTheStorage", async ({ page }) => {
  await page.addInitScript(() => {
    const counted = window as unknown as { persistAsked: number };
    counted.persistAsked = 0;
    StorageManager.prototype.persist = () => {
      counted.persistAsked += 1;
      return Promise.resolve(true);
    };
  });
  await openTraining(page);
  await page.getByRole("button", { name: nl("photos.title") }).click();
  await page.getByTestId("photos.picker").setInputFiles({ name: "voortgang.png", mimeType: "image/png", buffer: png() });
  await expect(page.getByTestId("photos.tile")).toHaveCount(1);
  await expect.poll(() => page.evaluate(() => (window as unknown as { persistAsked: number }).persistAsked)).toBeGreaterThan(0);
});
