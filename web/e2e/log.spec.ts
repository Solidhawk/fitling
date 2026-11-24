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

test("aShortQueryStaysLocal", async ({ page }) => {
  await start(page);
  await sharedProduct("ab");
  await search(page, "ab");
  await expect(page.getByText(nl("log.results.none"))).toBeVisible();
  await expect(page.getByRole("heading", { name: nl("log.results.online") })).toHaveCount(0);
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
  await expect(page.getByText("Oma's appeltaart")).toBeVisible();
  const { data } = await admin.from("products").select("kcal_100, search_name, owner_id").eq("owner_id", user.id).single();
  expect(data).toEqual({ kcal_100: 280.4, search_name: "oma's appeltaart", owner_id: user.id });
});

// Review Focus: without a connection nothing is stored and the portion stays as it was typed.
test("loggingWithoutAConnectionKeepsThePortion", async ({ page }) => {
  const user = await start(page);
  const product = await sharedProduct("Banaan");
  await search(page, product.name);
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  await page.getByTestId("portion.quantity").fill("120");
  await page.route("**/rest/v1/food_entries*", (route) => route.abort("internetdisconnected"));
  await page.getByTestId("portion.save").click();
  await expect(page.getByText(nl("error.network"))).toBeVisible();
  await expect(page.getByTestId("portion.quantity")).toHaveValue("120");
  const { data } = await admin.from("food_entries").select("id").eq("user_id", user.id);
  expect(data).toEqual([]);
});
