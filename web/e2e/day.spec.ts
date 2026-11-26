import AxeBuilder from "@axe-core/playwright";
import { readFileSync } from "node:fs";
import { expect, type Page, test } from "./fixtures";
import { admin, createUser, foodEntry, localDay, nl, nlCount, signIn } from "./users";

/** Signed in with a profile (2760 kcal) and a partner; the app opens on Vandaag. */
async function start(page: Page) {
  const user = await createUser({ profile: true, creature: true });
  await signIn(page, user.email);
  await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
  return user;
}

// vite preview sends the gzipped rules with Content-Encoding, so the browser unpacks them; a server that hands them over
// as they are (application/gzip) leaves that to the app, which unpacks them with DecompressionStream (useCore.ts).
// That way is checked here, in Safari too: otherwise WebAssembly would refuse the bytes and Vandaag would not show.
test("theAppUnpacksTheRulesItself", async ({ page }) => {
  const packed = readFileSync(new URL("../public/fitling-core.wasm.gz", import.meta.url));
  expect([...packed.subarray(0, 2)]).toEqual([0x1f, 0x8b]);
  let served = 0;
  await page.route("**/fitling-core.wasm.gz*", async (route) => {
    served += 1;
    await route.fulfill({ status: 200, contentType: "application/gzip", body: packed });
  });
  await start(page);
  expect(served).toBe(1);
});

function daysBefore(count: number): string {
  const date = new Date();
  date.setDate(date.getDate() - count);
  return localDay(date);
}

// DayOverviewTests on iOS.
test("usesTheTargetsThatAppliedOnThatDay", async ({ page }, info) => {
  const user = await start(page);
  await admin.from("target_history").insert({
    user_id: user.id,
    effective_on: daysBefore(3),
    kcal_target: 2000,
    protein_target_g: 120,
    carbs_target_g: 250,
    fat_target_g: 70,
    updated_at: new Date().toISOString(),
  });
  await expect(page.getByTestId("day.progress")).toContainText(/2\.760\s?kcal/);
  await page.screenshot({ path: `test-results/screens/${info.project.name}-vandaag-leeg.png` });
  await page.getByRole("button", { name: nl("day.previous") }).click();
  await expect(page.getByTestId("day.progress")).toContainText(/2\.000\s?kcal/);
});

test("reportsUnknownMacros", async ({ page }) => {
  const user = await start(page);
  await foodEntry(user.id, { consumed_on: localDay(), protein_g: null });
  await page.reload();
  await expect(page.getByText(nlCount("day.unknown.protein %lld", 1))).toBeVisible({ timeout: 15_000 });
});

test("waterAddsUp", async ({ page }) => {
  await start(page);
  await page.getByTestId("water.add").click();
  await expect(page.getByTestId("water.amount")).toHaveText(/250\s?ml/);
  await page.getByTestId("water.add").click();
  await expect(page.getByTestId("water.amount")).toHaveText(/500\s?ml/);
});

test("mealsAreKeptApartAndDeletedEntriesDisappear", async ({ page }, info) => {
  const user = await start(page);
  await foodEntry(user.id, { consumed_on: localDay(), meal: "breakfast", name: "Havermout", kcal: 300 });
  await foodEntry(user.id, { consumed_on: localDay(), meal: "lunch", name: "Soep", kcal: 150 });
  await page.reload();
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/300\s?kcal/, { timeout: 15_000 });
  await expect(page.getByTestId("day.kcal.lunch")).toHaveText(/150\s?kcal/);
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => violation.id)).toEqual([]);
  await page.screenshot({ path: `test-results/screens/${info.project.name}-vandaag-gelogd.png`, fullPage: true });
  // With the keyboard: the delete button after the row slides into view when it has the focus.
  await page.getByRole("button", { name: nl("day.delete") }).first().focus();
  await page.keyboard.press("Enter");
  await expect(page.getByText("Havermout")).toHaveCount(0);
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/0\s?kcal/);
  const { data } = await admin.from("food_entries").select("deleted_at").eq("user_id", user.id).eq("name", "Havermout").single();
  expect(data?.deleted_at).not.toBeNull();
});

// Phase 7: without a connection a deletion waits, as a log does; the entry is gone here, and later on the server too.
test("aDeletionWithoutAConnectionWaits", async ({ page }) => {
  const user = await start(page);
  await foodEntry(user.id, { consumed_on: localDay(), meal: "breakfast", name: "Havermout", kcal: 300 });
  await page.reload();
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/300\s?kcal/, { timeout: 15_000 });
  await page.route("**/rest/v1/food_entries*", (route) => route.abort("internetdisconnected"));
  await page.getByRole("button", { name: nl("day.delete") }).first().focus();
  await page.keyboard.press("Enter");
  await expect(page.getByText("Havermout")).toHaveCount(0);
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/0\s?kcal/);
  const waiting = await admin.from("food_entries").select("deleted_at").eq("user_id", user.id).single();
  expect(waiting.data?.deleted_at).toBeNull();
  await page.unroute("**/rest/v1/food_entries*");
  await page.reload();
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/0\s?kcal/, { timeout: 15_000 });
  await expect
    .poll(async () => (await admin.from("food_entries").select("deleted_at").eq("user_id", user.id).single()).data?.deleted_at ?? null)
    .not.toBeNull();
});

test("swipingAnEntryLeftShowsDelete", async ({ page }) => {
  const user = await start(page);
  await foodEntry(user.id, { consumed_on: localDay(), meal: "snack", name: "Appel", kcal: 52 });
  await page.reload();
  const row = page.getByTestId("day.entry").filter({ hasText: "Appel" });
  await expect(row).toBeVisible({ timeout: 15_000 });
  // The snack row lies below the fold on a phone, and the tab bar covers the bottom: in the middle of the screen.
  await row.evaluate((element) => element.scrollIntoView({ block: "center" }));
  const box = (await row.boundingBox())!;
  await page.mouse.move(box.x + box.width - 20, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width - 140, box.y + box.height / 2, { steps: 8 });
  await page.mouse.up();
  await page.getByRole("button", { name: nl("day.delete") }).click();
  await expect(page.getByText("Appel")).toHaveCount(0);
});

test("theFutureCannotBeShown", async ({ page }) => {
  await start(page);
  await expect(page.getByRole("button", { name: nl("day.next") })).toBeDisabled();
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(nl("day.today"));
});

test("theCardShowsThePartnersMood", async ({ page }) => {
  await start(page);
  await expect(page.locator(".day-card-mood")).toContainText("Uiltje");
  await expect(page.locator(".day-card .partner-canvas")).toBeVisible();
});

test.describe("around midnight in Tokyo", () => {
  // Without summer time, so 23.59 is the same offset all year.
  test.use({ timezoneId: "Asia/Tokyo" });

  // A meal logged at 23.59 belongs to that day; at 00.01 the next day starts empty (Review Focus).
  test("dayFollowsTheBrowsersDate", async ({ page }) => {
    const user = await start(page);
    const day = localDay();
    await foodEntry(user.id, { consumed_on: day, meal: "dinner", name: "Laat avondeten", kcal: 400 });
    await page.clock.setFixedTime(new Date(`${day}T23:59:00+09:00`));
    await page.reload();
    await expect(page.getByText("Laat avondeten")).toBeVisible({ timeout: 15_000 });
    const [year, month, date] = day.split("-").map(Number);
    const next = new Date(Date.UTC(year, month - 1, date + 1)).toISOString().slice(0, 10);
    await page.clock.setFixedTime(new Date(`${next}T00:01:00+09:00`));
    await page.reload();
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(nl("day.today"), { timeout: 15_000 });
    await expect(page.getByTestId("day.progress")).toBeVisible();
    await expect(page.getByText("Laat avondeten")).toHaveCount(0);
    await page.getByRole("button", { name: nl("day.previous") }).click();
    await expect(page.getByText("Laat avondeten")).toBeVisible();
  });

  function dayAfter(day: string, count: number): string {
    const [year, month, date] = day.split("-").map(Number);
    return new Date(Date.UTC(year, month - 1, date + count)).toISOString().slice(0, 10);
  }

  /** Signed in on `day` at 23.57 in Tokyo, with a dinner logged that evening. */
  async function eveningOf(page: Page, day: string, setClock: (time: Date) => Promise<void>) {
    const user = await createUser({ profile: true, creature: true });
    await foodEntry(user.id, { consumed_on: day, meal: "dinner", name: "Laat avondeten", kcal: 400 });
    await setClock(new Date(`${day}T23:57:00+09:00`));
    await signIn(page, user.email);
    await expect(page.getByText("Laat avondeten")).toBeVisible({ timeout: 15_000 });
    return user;
  }

  // Open since the evening: past midnight Vandaag moves on to the new day by itself, so breakfast does not land on
  // yesterday (UNFORGET S40).
  test("vandaagMovesOnAtMidnight", async ({ page }) => {
    await eveningOf(page, localDay(), (time) => page.clock.install({ time }));
    await page.clock.fastForward("05:00");
    await expect(page.getByText("Laat avondeten")).toHaveCount(0, { timeout: 15_000 });
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(nl("day.today"));
    await expect(page.getByRole("button", { name: nl("day.next") })).toBeDisabled();
  });

  // A laptop that slept past midnight: its timer comes late, so coming back to the tab is enough. The fixed clock keeps
  // the midnight timer out of it (real timers, a minute away).
  test("backInTheTabTheNextMorningShowsThatDay", async ({ page }) => {
    const day = localDay();
    await eveningOf(page, day, (time) => page.clock.setFixedTime(time));
    await page.clock.setFixedTime(new Date(`${dayAfter(day, 1)}T08:00:00+09:00`));
    await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
    await expect(page.getByText("Laat avondeten")).toHaveCount(0, { timeout: 15_000 });
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(nl("day.today"));
  });

  // Looking back on purpose: that day stays when the date moves on.
  test("aDayLookedBackAtStaysPastMidnight", async ({ page }) => {
    const day = localDay();
    const user = await eveningOf(page, day, (time) => page.clock.install({ time }));
    await foodEntry(user.id, { consumed_on: dayAfter(day, -1), meal: "lunch", name: "De dag ervoor gegeten", kcal: 300 });
    await page.getByRole("button", { name: nl("day.previous") }).click();
    await expect(page.getByText("De dag ervoor gegeten")).toBeVisible({ timeout: 15_000 });
    await page.clock.fastForward("05:00");
    await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
    await expect(page.getByText("De dag ervoor gegeten")).toBeVisible();
    await expect(page.getByRole("heading", { level: 1 })).not.toHaveText(nl("day.today"));
  });
});

// Review: tapping back twice quickly shows the second day, even when the first day's answer comes in last.
test("switchingDaysQuicklyShowsTheLastDay", async ({ page }) => {
  const user = await start(page);
  await foodEntry(user.id, { consumed_on: daysBefore(1), name: "Gisteren gegeten" });
  await foodEntry(user.id, { consumed_on: daysBefore(2), name: "De dag ervoor gegeten" });
  await page.route(`**/rest/v1/food_entries*consumed_on=eq.${daysBefore(1)}*`, async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 1500));
    await route.continue();
  });
  await page.getByRole("button", { name: nl("day.previous") }).click();
  await page.getByRole("button", { name: nl("day.previous") }).click();
  await expect(page.getByText("De dag ervoor gegeten")).toBeVisible({ timeout: 15_000 });
  await page.waitForTimeout(2000);
  await expect(page.getByText("De dag ervoor gegeten")).toBeVisible();
  await expect(page.getByText("Gisteren gegeten", { exact: true })).toHaveCount(0);
});
