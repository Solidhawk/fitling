import { expect, type Page, test } from "./fixtures";
import { admin, createUser, nl, sharedProduct, signIn } from "./users";

/** On Vandaag with a profile and a partner, the log sheet for breakfast open. */
async function start(page: Page) {
  const user = await createUser({ profile: true, creature: true });
  await signIn(page, user.email);
  await page.getByTestId("day.add.breakfast").click({ timeout: 15_000 });
  await expect(page.locator('[data-screen="logFood"]')).toBeVisible();
  return user;
}

async function search(page: Page, text: string) {
  await page.getByTestId("log.search").fill(text);
}

// The log sheet says "Nog niets gelogd" once it knows, not while recent and favourites are still being read; and a list
// that cannot be read does not hide the other (review of web phase 2, S58).
test("theEmptyLogSheetWaitsForItsLists", async ({ page }) => {
  const user = await createUser({ profile: true, creature: true });
  const product = await sharedProduct("Krentenbol");
  await admin.from("favorite_products").insert({ user_id: user.id, product_id: product.id, updated_at: new Date().toISOString() });
  // Recent (food_entries read for its products) comes slowly, and then not at all.
  await page.route("**/rest/v1/food_entries*", async (route) => {
    if (route.request().method() === "GET" && route.request().url().includes("product_id")) {
      await new Promise((resolve) => setTimeout(resolve, 2_000));
      await route.fulfill({ status: 500, contentType: "application/json", body: "{}" });
      return;
    }
    await route.continue();
  });
  await signIn(page, user.email);
  await page.getByTestId("day.add.breakfast").click({ timeout: 15_000 });
  await expect(page.locator('[data-screen="logFood"]')).toBeVisible();
  await expect(page.getByText(nl("log.empty"))).toHaveCount(0);
  // The favourite shows without waiting for recent; recent's failure is told, and "Nog niets gelogd" would not be true.
  await expect(page.getByRole("button", { name: new RegExp(product.name) })).toBeVisible({ timeout: 10_000 });
  await expect(page.getByRole("alertdialog", { name: nl("error.server") })).toBeVisible();
  await expect(page.getByText(nl("log.empty"))).toHaveCount(0);
});

// FoodLogTests and testLogAScannedProduct on iOS.
test("logAProductFromSearch", async ({ page }, info) => {
  const user = await start(page);
  const product = await sharedProduct("Volkorenbrood");
  await page.screenshot({ path: `test-results/screens/${info.project.name}-loggen.png` });
  await search(page, product.name);
  await expect(page.getByRole("heading", { name: nl("log.results.online") })).toBeVisible();
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  await expect(page.getByTestId("portion.quantity")).toHaveValue("100");
  await expect(page.getByTestId("portion.energy")).toHaveText(/250\s?kcal/);
  await page.screenshot({ path: `test-results/screens/${info.project.name}-portie.png`, fullPage: true });
  await page.getByTestId("portion.save").click();
  await expect(page.locator('[data-screen="logFood"]')).toHaveCount(0);
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/250\s?kcal/);
  const { data } = await admin.from("food_entries").select("name, kcal, product_id").eq("user_id", user.id).single();
  expect(data).toEqual({ name: product.name, kcal: 250, product_id: product.id });
});

test("servingsUseTheServingSize", async ({ page }) => {
  const user = await start(page);
  const product = await sharedProduct("Muesli", { serving_size: 45 });
  await search(page, product.name);
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  await expect(page.getByRole("radio", { name: nl("portion.unit.serving") })).toHaveAttribute("aria-checked", "true");
  await expect(page.getByTestId("portion.quantity")).toHaveValue("1");
  await page.getByTestId("portion.save").click();
  await expect(page.getByText(nl("portion.servings %@").replace("%@", "1"))).toBeVisible();
  const { data } = await admin.from("food_entries").select("kcal, quantity_unit").eq("user_id", user.id).single();
  expect(data).toEqual({ kcal: 112.5, quantity_unit: "serving" });
});

// S40: a segment looks as on iOS (36 px), but can be tapped over 44 px, as Apple asks of every control.
test("segmentsAreBigEnoughToTap", async ({ page }) => {
  await start(page);
  const product = await sharedProduct("Cruesli", { serving_size: 45 });
  await search(page, product.name);
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  const segments = await page.getByRole("radio").all();
  expect(segments.length).toBeGreaterThan(1);
  for (const segment of segments) {
    const box = await segment.boundingBox();
    if (!box) throw new Error("segment not shown");
    const middle = box.x + box.width / 2;
    // Tapping 4 px above or below the drawn segment still hits it: 36 + 2 × 4 = 44.
    for (const y of [box.y - 3.5, box.y + box.height + 3.5]) {
      const hit = await page.evaluate(({ x, y }) => document.elementFromPoint(x, y)?.closest('[role="radio"]')?.textContent, { x: middle, y });
      expect(hit).toBe(await segment.textContent());
    }
  }
});

test("productWithoutKcalAsksForIt", async ({ page }) => {
  const user = await start(page);
  const product = await sharedProduct("Kruidenthee", { kcal_100: null });
  await search(page, product.name);
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  await expect(page.getByTestId("portion.save")).toBeDisabled();
  await page.getByTestId("portion.kcal").fill("3");
  await page.getByTestId("portion.save").click();
  await expect(page.locator('[data-screen="logFood"]')).toHaveCount(0);
  const { data: entry } = await admin.from("food_entries").select("product_id").eq("user_id", user.id).single();
  expect(entry?.product_id).not.toBe(product.id);
  const { data: own } = await admin.from("products").select("owner_id, kcal_100").eq("id", entry?.product_id).single();
  expect(own).toEqual({ owner_id: user.id, kcal_100: 3 });
  const { data: shared } = await admin.from("products").select("kcal_100").eq("id", product.id).single();
  expect(shared).toEqual({ kcal_100: null });
});

test("favoriteShowsUpAtTheTop", async ({ page }) => {
  await start(page);
  const product = await sharedProduct("Yoghurt");
  await search(page, product.name);
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  await page.getByRole("button", { name: nl("portion.favorite.add") }).click();
  await expect(page.getByRole("button", { name: nl("portion.favorite.remove") })).toBeVisible();
  await page.getByTestId("portion.save").click();
  await page.getByTestId("day.add.lunch").click();
  await expect(page.getByRole("heading", { name: nl("log.favorites") })).toBeVisible();
  await expect(page.getByRole("button", { name: new RegExp(product.name) }).first()).toBeVisible();
});

test("recentShowsEachProductOnce", async ({ page }) => {
  await start(page);
  const product = await sharedProduct("Kaas");
  for (const meal of ["breakfast", "lunch"]) {
    if (meal === "lunch") await page.getByTestId("day.add.lunch").click();
    await search(page, product.name);
    await page.getByRole("button", { name: new RegExp(product.name) }).first().click();
    await page.getByTestId("portion.save").click();
    await expect(page.locator('[data-screen="logFood"]')).toHaveCount(0);
  }
  await page.getByTestId("day.add.dinner").click();
  await expect(page.getByRole("heading", { name: nl("log.recent") })).toBeVisible();
  await expect(page.getByRole("button", { name: new RegExp(product.name) })).toHaveCount(1);
});

// Two letters search the user's own products, not the shared ones. Checked once the search is done (review of web phase
// 2: before, the test passed in the pause before the app searched at all).
test("aShortQueryStaysLocal", async ({ page }) => {
  await start(page);
  await sharedProduct("ab");
  const shared: string[] = [];
  page.on("request", (request) => {
    if (/\/rest\/v1\/products\?.*owner_id=is\.null/.test(request.url())) shared.push(request.url());
  });
  const own = page.waitForResponse((response) => /\/rest\/v1\/products\?.*owner_id=not\.is\.null/.test(response.url()));
  await search(page, "ab");
  await own;
  await expect(page.getByText(nl("log.results.none"))).toBeVisible();
  await expect(page.getByRole("heading", { name: nl("log.results.online") })).toHaveCount(0);
  expect(shared).toEqual([]);
});

test("addAnOwnProductAndLogIt", async ({ page }, info) => {
  const user = await start(page);
  await page.getByTestId("log.ownProduct").click();
  await page.getByTestId("product.add.name").fill("Oma's appeltaart");
  await expect(page.getByTestId("product.add.save")).toBeDisabled();
  await page.getByTestId("product.add.kcal").fill("280,44");
  await page.getByTestId("product.add.serving").fill("120");
  await page.screenshot({ path: `test-results/screens/${info.project.name}-eigen-product.png`, fullPage: true });
  await page.getByTestId("product.add.save").click();
  await expect(page.getByTestId("portion.quantity")).toHaveValue("1");
  await page.getByTestId("portion.save").click();
  await expect(page.locator('[data-screen="logFood"]')).toHaveCount(0);
  await expect(page.getByTestId("day.entry").filter({ hasText: "Oma's appeltaart" })).toBeVisible();
  const { data } = await admin.from("products").select("kcal_100, search_name, owner_id").eq("owner_id", user.id).single();
  expect(data).toEqual({ kcal_100: 280.4, search_name: "oma's appeltaart", owner_id: user.id });
});

// Phase 7: without a connection the portion is logged all the same and waits in this browser, as on the iPhone; it
// arrives once the app can send it.
test("loggingWithoutAConnectionWaitsForIt", async ({ page }) => {
  const user = await start(page);
  const product = await sharedProduct("Banaan");
  await search(page, product.name);
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  await page.getByTestId("portion.quantity").fill("120");
  await page.route("**/rest/v1/food_entries*", (route) => route.abort("internetdisconnected"));
  await page.getByTestId("portion.save").click();
  await expect(page.locator('[data-screen="logFood"]')).toHaveCount(0);
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/300\s?kcal/);
  const { data } = await admin.from("food_entries").select("id").eq("user_id", user.id);
  expect(data).toEqual([]);
  await page.unroute("**/rest/v1/food_entries*");
  await page.reload();
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/300\s?kcal/, { timeout: 15_000 });
  await expect.poll(async () => (await admin.from("food_entries").select("kcal").eq("user_id", user.id)).data).toEqual([{ kcal: 300 }]);
});

/** Logs a fresh product with the server's answers to writing food entries replaced by `answer`. */
async function logWith(page: Page, name: string, answer: Parameters<Page["route"]>[1]) {
  const product = await sharedProduct(name);
  await search(page, product.name);
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  await page.route("**/rest/v1/food_entries*", answer);
  await page.getByTestId("portion.save").click();
  await expect(page.locator('[data-screen="logFood"]')).toHaveCount(0);
}

const waitingWrites = (page: Page, userID: string) =>
  page.evaluate(
    (key) => (JSON.parse(localStorage.getItem(key) ?? "[]") as { sentAt?: number }[]).filter((write) => write.sentAt === undefined).length,
    `fitling.offline.${userID}.writes`,
  );

// Signing out erases what still waits, so it asks first, as AccountView does on the iPhone.
test("signingOutWithAWaitingLogAsksFirst", async ({ page }) => {
  await start(page);
  await logWith(page, "Peer", (route) => route.abort("internetdisconnected"));
  await page.getByRole("tab", { name: nl("profile.title") }).click();
  await page.getByRole("button", { name: nl("account.title") }).click();
  await page.getByRole("button", { name: nl("account.signOut") }).click();
  await expect(page.getByRole("alertdialog", { name: nl("account.unsynced.title") })).toBeVisible();
  await expect(page.getByText(nl("account.unsynced.body.web"))).toBeVisible();
  await page.getByRole("button", { name: nl("common.cancel") }).click();
  await expect(page.locator('[data-page="account"]')).toBeVisible();
  await page.getByRole("button", { name: nl("account.signOut") }).click();
  await page.getByRole("button", { name: nl("account.unsynced.force") }).click();
  await expect(page.locator('[data-screen="welcome"]')).toBeAttached();
});

// Fable's review of phase 7: a log the server keeps turning down although it answers (a token, a policy) waits, and
// Vandaag says that not everything is saved, until it goes through.
test("aLogTheServerKeepsTurningDownSaysSo", async ({ page }) => {
  const user = await start(page);
  await logWith(page, "Kiwi", (route) =>
    route.request().method() === "POST"
      ? route.fulfill({
          status: 401,
          contentType: "application/json",
          body: JSON.stringify({ code: "PGRST301", message: "JWT expired", details: null, hint: null }),
        })
      : route.continue(),
  );
  await expect(page.getByTestId("day.unsaved")).toHaveText(nl("account.unsynced.title"));
  await page.unroute("**/rest/v1/food_entries*");
  await page.reload();
  await expect.poll(async () => (await admin.from("food_entries").select("id").eq("user_id", user.id)).data?.length, { timeout: 15_000 }).toBe(1);
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/250\s?kcal/, { timeout: 15_000 });
  await expect(page.getByTestId("day.unsaved")).toHaveCount(0);
});

// A log that waited and is refused for good when it is sent later is told once, not dropped in silence.
test("aWaitingLogRefusedLaterIsTold", async ({ page }) => {
  const user = await start(page);
  await logWith(page, "Mango", (route) => route.abort("internetdisconnected"));
  await page.unroute("**/rest/v1/food_entries*");
  await page.route("**/rest/v1/food_entries*", (route) =>
    route.request().method() === "POST"
      ? route.fulfill({
          status: 400,
          contentType: "application/json",
          body: JSON.stringify({ code: "23514", message: "new row violates check constraint", details: null, hint: null }),
        })
      : route.continue(),
  );
  await page.reload();
  // Sent at sign-in and refused: Vandaag says so at once, without another visit.
  await expect(page.getByRole("alertdialog", { name: nl("offline.refused") })).toBeVisible({ timeout: 15_000 });
  expect(await waitingWrites(page, user.id)).toBe(0);
  await page.getByRole("button", { name: nl("common.ok") }).click();
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/0\s?kcal/);
});

// Review: a failed first try must not leave an own copy behind for every retry (FoodDiary keeps its copy).
test("aRetryUsesTheOwnCopyMadeTheFirstTime", async ({ page }) => {
  const user = await start(page);
  const product = await sharedProduct("Rooibos", { kcal_100: null });
  await search(page, product.name);
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  await page.getByTestId("portion.kcal").fill("2");
  // The server turns the entry down once, for a rule it breaks: that never passes later, so the portion stays to try
  // again and the entry is not kept to be sent.
  await page.route("**/rest/v1/food_entries*", (route) =>
    route.request().method() === "POST"
      ? route.fulfill({
          status: 400,
          contentType: "application/json",
          body: JSON.stringify({ code: "23514", message: "new row violates check constraint", details: null, hint: null }),
        })
      : route.continue(),
  );
  await page.getByTestId("portion.save").click();
  await expect(page.getByText(nl("error.server"))).toBeVisible();
  await page.unroute("**/rest/v1/food_entries*");
  await page.getByTestId("portion.save").click();
  await expect(page.locator('[data-screen="logFood"]')).toHaveCount(0);
  const { data } = await admin.from("products").select("id").eq("owner_id", user.id);
  expect(data).toHaveLength(1);
  const { data: entries } = await admin.from("food_entries").select("id").eq("user_id", user.id);
  expect(entries).toHaveLength(1);
});

// PortionView: without an amount there is nothing to add and nothing to save.
test("anEmptyAmountCannotBeSaved", async ({ page }) => {
  await start(page);
  const product = await sharedProduct("Rijst");
  await search(page, product.name);
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  await page.getByTestId("portion.quantity").fill("");
  await expect(page.getByTestId("portion.save")).toBeDisabled();
  await expect(page.getByTestId("portion.energy")).toHaveCount(0);
});
