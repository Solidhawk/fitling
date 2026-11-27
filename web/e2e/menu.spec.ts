import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "./fixtures";
import { openMenu, sharedRecipe, todaysMenu } from "./menu";
import { admin, createUser, localDay, nl, nlCount, signIn } from "./users";

// MenuTests and the menu UI tests on iOS: the week menu, its recipes and the user's own (web phase 5).

test("aWeekMenuIsMade", async ({ page }, info) => {
  const user = await openMenu(page);
  await expect(page.getByText(nl("menu.empty"))).toBeVisible();
  await page.getByTestId("menu.generate.first").click();
  // The generator opens with a week and the daily target.
  await expect(page.getByTestId("menu.generator.days")).toContainText(nlCount("menu.generator.days %lld", 7));
  await expect(page.getByTestId("menu.generator.goal.daily")).toHaveAttribute("aria-checked", "true");
  await expect(page.getByTestId("menu.generator.goal.daily")).toContainText(nl("menu.generator.goal.kcal %lld").replace("%lld", "2.760"));
  await page.getByTestId("menu.generator.days").getByRole("button", { name: nl("common.decrease") }).click();
  await page.getByTestId("menu.generator.days").getByRole("button", { name: nl("common.decrease") }).click();
  await page.screenshot({ path: `test-results/screens/${info.project.name}-menu-maken.png` });
  await page.getByTestId("menu.generator.make").click();
  await expect(page.getByTestId(`menu.day.renew.${localDay()}`)).toBeVisible({ timeout: 15_000 });
  await page.screenshot({ path: `test-results/screens/${info.project.name}-weekmenu.png`, fullPage: true });
  const { data } = await admin.from("meal_plan_entries").select("planned_on").eq("user_id", user.id).is("deleted_at", null);
  // Five days of breakfast, lunch and dinner, as the preferences start.
  expect(data).toHaveLength(15);
  expect(new Set(data!.map((row) => row.planned_on)).size).toBe(5);
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => violation.id)).toEqual([]);
  // The next menu opens with these choices; another goal plans for its own kcal and is remembered too.
  await page.getByTestId("menu.generate").click();
  await expect(page.getByTestId("menu.generator.days")).toContainText(nlCount("menu.generator.days %lld", 5));
  const kcalOf = async (goal: string) => Number((await page.getByTestId(`menu.generator.goal.${goal}`).innerText()).replace(/\D/g, ""));
  expect(await kcalOf("lose")).toBeLessThan(await kcalOf("daily"));
  await page.getByTestId("menu.generator.goal.lose").click();
  await page.getByTestId("menu.generator.make").click();
  await expect(page.getByTestId("menu.generate")).toBeVisible({ timeout: 15_000 });
  await page.getByTestId("menu.generate").click();
  await expect(page.getByTestId("menu.generator.goal.lose")).toHaveAttribute("aria-checked", "true");
});

test("aMealIsLoggedOnce", async ({ page }) => {
  let planned: Awaited<ReturnType<typeof todaysMenu>> = [];
  const user = await openMenu(page, async (userID) => {
    planned = await todaysMenu(userID);
  });
  const dinner = planned.find((meal) => meal.slot === "dinner")!;
  // Swiping the row to the right uncovers Eaten (swipeActions(edge: .leading)).
  const row = page.getByTestId(`menu.entry.${dinner.id}`);
  // Clear of the tab bar, which covers the bottom of the screen.
  await row.evaluate((element) => element.scrollIntoView({ block: "center" }));
  const box = (await row.boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 + 140, box.y + box.height / 2, { steps: 8 });
  await page.mouse.up();
  await page.getByTestId(`menu.log.${dinner.id}`).click();
  await expect(page.getByTestId(`menu.logged.${dinner.id}`)).toBeVisible({ timeout: 15_000 });
  // Logged meals have no actions left.
  await expect(page.getByTestId(`menu.log.${dinner.id}`)).toHaveCount(0);
  const { data } = await admin.from("food_entries").select("name, quantity_unit, recipe_id, kcal").eq("user_id", user.id);
  expect(data).toEqual([{ name: dinner.recipe.title, quantity_unit: "serving", recipe_id: dinner.recipe.id, kcal: dinner.recipe.kcal }]);
  await page.getByRole("tab", { name: nl("tab.today") }).click();
  await expect(page.getByTestId("day.entry")).toContainText(dinner.recipe.title, { timeout: 15_000 });
});

test("aSwappedMealIsPinned", async ({ page }, info) => {
  let planned: Awaited<ReturnType<typeof todaysMenu>> = [];
  await openMenu(page, async (userID) => {
    planned = await todaysMenu(userID);
  });
  const lunch = planned.find((meal) => meal.slot === "lunch")!;
  const other = await sharedRecipe("lunch", 1);
  // The row's menu, as a long press on iOS (contextMenu).
  await page.getByTestId(`menu.entry.${lunch.id}`).click({ button: "right" });
  await expect(page.getByRole("alertdialog", { name: lunch.recipe.title })).toBeVisible();
  await page.screenshot({ path: `test-results/screens/${info.project.name}-menu-acties.png` });
  await page.getByRole("alertdialog").getByRole("button", { name: nl("menu.swap") }).click();
  await page.getByTestId("menu.picker.search").fill(other.title.slice(0, 6));
  await page.getByTestId(`menu.picker.recipe.${other.id}`).click();
  await expect(page.getByTestId(`menu.entry.${lunch.id}`)).toContainText(other.title, { timeout: 15_000 });
  await expect(page.getByTestId(`menu.pinned.${lunch.id}`)).toBeVisible();
  // Removing it from the menu (Weghalen).
  await page.getByTestId(`menu.entry.${lunch.id}`).click({ button: "right" });
  await page.getByRole("alertdialog").getByRole("button", { name: nl("menu.remove") }).click();
  await expect(page.getByTestId(`menu.entry.${lunch.id}`)).toHaveCount(0, { timeout: 15_000 });
});

test("renewingADayLeavesPinnedMeals", async ({ page }) => {
  let planned: Awaited<ReturnType<typeof todaysMenu>> = [];
  await openMenu(page, async (userID) => {
    planned = await todaysMenu(userID);
    await admin.from("meal_plan_entries").update({ is_pinned: true }).eq("id", planned[0].id);
  });
  await expect(page.getByTestId(`menu.pinned.${planned[0].id}`)).toBeVisible();
  await page.getByTestId(`menu.day.renew.${localDay()}`).click();
  await expect(page.getByTestId(`menu.entry.${planned[2].id}`)).toHaveCount(0, { timeout: 15_000 });
  await expect(page.getByTestId(`menu.entry.${planned[1].id}`)).toHaveCount(0);
  await expect(page.getByTestId(`menu.entry.${planned[0].id}`)).toBeVisible();
});

test("aRecipeShowsItsPhotoAndCredit", async ({ page }, info) => {
  let planned: Awaited<ReturnType<typeof todaysMenu>> = [];
  await openMenu(page, async (userID) => {
    planned = await todaysMenu(userID);
  });
  const breakfast = planned[0];
  await page.getByTestId(`menu.entry.${breakfast.id}`).click();
  await expect(page.getByRole("heading", { name: breakfast.recipe.title })).toBeVisible();
  await expect(page.getByTestId("menu.recipe.kcal")).toContainText(`${Math.round(breakfast.recipe.kcal)} kcal`);
  await expect(page.getByText(/Wikimedia Commons/)).toBeVisible();
  await expect.poll(() => page.locator("img.recipe-photo").evaluate((image: HTMLImageElement) => image.naturalWidth)).toBeGreaterThan(0);
  await expect(page.getByRole("heading", { name: nl("menu.recipe.steps") })).toBeVisible();
  await page.screenshot({ path: `test-results/screens/${info.project.name}-recept.png`, fullPage: true });
  // Back to the menu through the browser's history, as swiping back.
  await page.goBack();
  await expect(page.getByTestId(`menu.entry.${breakfast.id}`)).toBeVisible();
});

test("anOwnRecipeIsMadeAndRemoved", async ({ page }, info) => {
  const user = await openMenu(page);
  await page.getByTestId("menu.recipes").click();
  await page.getByTestId("menu.recipe.new").click();
  await page.getByTestId("menu.own.title").fill("Pasta pesto");
  await page.getByTestId("menu.own.kcal").fill("550");
  await page.getByTestId("menu.own.protein").fill("18");
  await page.getByTestId("menu.own.carbs").fill("70");
  // Without fat it is not complete yet.
  await expect(page.getByRole("button", { name: nl("common.save") })).toBeDisabled();
  await page.getByTestId("menu.own.fat").fill("20,5");
  await page.getByTestId("menu.own.ingredient").fill("Pasta");
  await page.getByTestId("menu.own.quantity").fill("200");
  await page.getByTestId("menu.own.addIngredient").click();
  await expect(page.getByText("200 g Pasta")).toBeVisible();
  await page.screenshot({ path: `test-results/screens/${info.project.name}-eigen-recept.png`, fullPage: true });
  await page.getByRole("button", { name: nl("common.save") }).click();
  await expect(page.getByText("Pasta pesto")).toBeVisible({ timeout: 15_000 });
  const { data } = await admin.from("recipes").select("id, fat_g_per_serving, meal_slots").eq("owner_id", user.id);
  expect(data).toEqual([{ id: data![0].id, fat_g_per_serving: 20.5, meal_slots: ["dinner"] }]);
  // Own recipes can be deleted from the list: with the keyboard, the button after the row slides into view.
  await page.getByRole("button", { name: nl("menu.recipe.delete") }).focus();
  await page.keyboard.press("Enter");
  await expect(page.getByText("Pasta pesto")).toHaveCount(0, { timeout: 15_000 });
});

// The ingredients did not reach the server: saving again stores the recipe once, with its ingredients (UNFORGET S46).
test("anOwnRecipeSavedAgainAfterAFailureIsStoredOnce", async ({ page }) => {
  const user = await openMenu(page);
  await page.getByTestId("menu.recipes").click();
  await page.getByTestId("menu.recipe.new").click();
  await page.getByTestId("menu.own.title").fill("Pasta pesto");
  await page.getByTestId("menu.own.kcal").fill("550");
  await page.getByTestId("menu.own.protein").fill("18");
  await page.getByTestId("menu.own.carbs").fill("70");
  await page.getByTestId("menu.own.fat").fill("20,5");
  await page.getByTestId("menu.own.ingredient").fill("Pasta");
  await page.getByTestId("menu.own.quantity").fill("200");
  await page.getByTestId("menu.own.addIngredient").click();
  let failures = 1;
  await page.route("**/rest/v1/recipe_ingredients*", async (route) => {
    if (route.request().method() === "POST" && failures-- > 0) {
      return route.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ message: "unavailable" }) });
    }
    return route.continue();
  });
  await page.getByRole("button", { name: nl("common.save") }).click();
  await page.getByRole("alertdialog").getByRole("button").click();
  await page.getByRole("button", { name: nl("common.save") }).click();
  await expect(page.getByText("Pasta pesto")).toBeVisible({ timeout: 15_000 });
  const { data: recipes } = await admin.from("recipes").select("id").eq("owner_id", user.id);
  expect(recipes).toHaveLength(1);
  const { data: lines } = await admin.from("recipe_ingredients").select("recipe_id").eq("owner_id", user.id);
  expect(lines).toEqual([{ recipe_id: recipes![0].id }]);
});

// The first save reached the server but its answer did not, and the user then changed the lines: saving again keeps the
// lines as they are now (UNFORGET S46, review).
test("linesChangedAfterALostAnswerAreTheOnesKept", async ({ page }) => {
  const user = await openMenu(page);
  await page.getByTestId("menu.recipes").click();
  await page.getByTestId("menu.recipe.new").click();
  await page.getByTestId("menu.own.title").fill("Pasta pesto");
  await page.getByTestId("menu.own.kcal").fill("550");
  await page.getByTestId("menu.own.protein").fill("18");
  await page.getByTestId("menu.own.carbs").fill("70");
  await page.getByTestId("menu.own.fat").fill("20,5");
  await page.getByTestId("menu.own.ingredient").fill("Pasta");
  await page.getByTestId("menu.own.quantity").fill("200");
  await page.getByTestId("menu.own.addIngredient").click();
  let lost = 1;
  await page.route("**/rest/v1/recipe_ingredients*", async (route) => {
    if (route.request().method() === "POST" && lost-- > 0) {
      // Stored on the server; the answer never arrives.
      await route.fetch();
      return route.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ message: "unavailable" }) });
    }
    return route.continue();
  });
  await page.getByRole("button", { name: nl("common.save") }).click();
  await page.getByRole("alertdialog").getByRole("button").click();
  await page.getByRole("dialog").getByRole("button", { name: nl("menu.recipe.delete") }).focus();
  await page.keyboard.press("Enter");
  await page.getByTestId("menu.own.ingredient").fill("Rijst");
  await page.getByTestId("menu.own.quantity").fill("150");
  await page.getByTestId("menu.own.addIngredient").click();
  await page.getByRole("button", { name: nl("common.save") }).click();
  await expect(page.getByText("Pasta pesto")).toBeVisible({ timeout: 15_000 });
  const { data: recipes } = await admin.from("recipes").select("id").eq("owner_id", user.id);
  expect(recipes).toHaveLength(1);
  const { data: lines } = await admin.from("recipe_ingredients").select("name").eq("owner_id", user.id).is("deleted_at", null);
  expect(lines).toEqual([{ name: { nl: "Rijst" } }]);
});

test("preferencesAreSavedAtOnce", async ({ page }) => {
  const user = await openMenu(page);
  await page.getByTestId("menu.preferences").click();
  // Every change is saved at once, so there is only OK, as on iOS.
  await expect(page.getByRole("dialog").getByRole("button", { name: nl("common.cancel"), exact: true })).toHaveCount(0);
  await page.getByTestId("menu.prefs.tag.fish").check();
  await page.getByTestId("menu.prefs.slot.breakfast").uncheck();
  await page.getByRole("button", { name: nl("common.ok"), exact: true }).click();
  await expect
    .poll(async () => (await admin.from("menu_preferences").select("excluded_tags, meal_slots").eq("user_id", user.id)).data)
    .toEqual([{ excluded_tags: ["fish"], meal_slots: ["lunch", "dinner"] }]);
});

test("aMealWhoseRecipeIsGoneStillShows", async ({ page }) => {
  // An own recipe on the menu, removed on another device afterwards: the menu still opens, the meal stays to swap.
  const entryID = crypto.randomUUID();
  await openMenu(page, async (userID) => {
    const recipeID = crypto.randomUUID();
    const now = new Date().toISOString();
    const recipe = await admin.from("recipes").insert({
      id: recipeID,
      owner_id: userID,
      title: { nl: "Weggehaald gerecht" },
      servings: 1,
      cook_minutes: 10,
      kcal_per_serving: 500,
      protein_g_per_serving: 20,
      carbs_g_per_serving: 50,
      fat_g_per_serving: 20,
      meal_slots: ["dinner"],
      updated_at: now,
      deleted_at: now,
    });
    if (recipe.error) throw recipe.error;
    const entry = await admin
      .from("meal_plan_entries")
      .insert({ id: entryID, user_id: userID, planned_on: localDay(), meal: "dinner", recipe_id: recipeID, servings: 1, updated_at: now });
    if (entry.error) throw entry.error;
  });
  // It keeps its name and opens its recipe, as on iOS; it is no longer offered in the recipe list.
  await expect(page.getByTestId(`menu.entry.${entryID}`)).toContainText("Weggehaald gerecht", { timeout: 15_000 });
  await page.getByTestId(`menu.entry.${entryID}`).click();
  await expect(page.getByRole("heading", { name: "Weggehaald gerecht" })).toBeVisible();
  await page.goBack();
  await page.getByTestId("menu.recipes").click();
  await expect(page.getByTestId("menu.recipe.new")).toBeVisible();
  await expect(page.getByText("Weggehaald gerecht")).toHaveCount(0);
  await page.goBack();
  // And it can still be logged.
  await page.getByTestId(`menu.log.${entryID}`).focus();
  await page.keyboard.press("Enter");
  await expect(page.getByTestId(`menu.logged.${entryID}`)).toBeVisible({ timeout: 15_000 });
});

/** A week of breakfast, lunch and dinner from today on, as a menu the app made; answers the entries' ids by day. */
async function weekMenu(userID: string): Promise<string[][]> {
  const days: string[][] = [];
  const rows = [];
  for (let offset = 0; offset < 7; offset++) {
    const date = new Date();
    date.setDate(date.getDate() + offset);
    const ids: string[] = [];
    for (const slot of ["breakfast", "lunch", "dinner"]) {
      const id = crypto.randomUUID();
      ids.push(id);
      const recipe = await sharedRecipe(slot, offset % 2);
      rows.push({ id, user_id: userID, planned_on: localDay(date), meal: slot, recipe_id: recipe.id, servings: 1, updated_at: new Date().toISOString() });
    }
    days.push(ids);
  }
  const stored = await admin.from("meal_plan_entries").insert(rows);
  if (stored.error) throw stored.error;
  return days;
}

// Back from a recipe the menu is where it was left, as a NavigationStack keeps it (the browser brings the place back
// with the history entry); a new screen opens at the top (UNFORGET S46).
test("backFromARecipeTheMenuIsWhereItWasLeft", async ({ page }) => {
  let week: string[][] = [];
  await openMenu(page, async (userID) => {
    week = await weekMenu(userID);
  });
  const entry = page.getByTestId(`menu.entry.${week[4][2]}`);
  await expect(entry).toBeVisible({ timeout: 15_000 });
  await entry.evaluate((element) => element.scrollIntoView({ block: "center" }));
  const left = await page.evaluate(() => window.scrollY);
  expect(left).toBeGreaterThan(100);
  await entry.click();
  await expect(page.locator('[data-page="recipe"]')).toBeVisible();
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
  await page.goBack();
  await expect(entry).toBeVisible();
  await expect.poll(async () => Math.abs((await page.evaluate(() => window.scrollY)) - left)).toBeLessThanOrEqual(2);
});

// A profile that cannot be read leaves the menu in view: only making a menu needs it, and that says it did not work
// and stays usable; once the profile is there again, it works (UNFORGET S58, S46).
test("theMenuShowsWithoutTheProfile", async ({ page }) => {
  const user = await createUser({ profile: true, creature: true });
  const planned = await todaysMenu(user.id);
  await signIn(page, user.email);
  await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
  await page.route("**/rest/v1/profiles*", (route) =>
    route.request().method() === "GET"
      ? route.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ message: "unavailable" }) })
      : route.continue(),
  );
  await page.getByRole("tab", { name: nl("menu.title") }).click();
  await expect(page.getByTestId(`menu.entry.${planned[0].id}`)).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole("alertdialog")).toHaveCount(0);
  await page.getByTestId("menu.generate").click();
  await expect(page.getByRole("alertdialog", { name: nl("error.server") })).toBeVisible();
  await page.getByRole("alertdialog").getByRole("button").click();
  await page.getByTestId(`menu.day.renew.${localDay()}`).click();
  await expect(page.getByRole("alertdialog", { name: nl("error.server") })).toBeVisible();
  await page.getByRole("alertdialog").getByRole("button").click();
  // The profile is back: the generator opens, and the day gets new meals.
  await page.unroute("**/rest/v1/profiles*");
  await page.getByTestId("menu.generate").click();
  await expect(page.getByTestId("menu.generator.make")).toBeVisible({ timeout: 15_000 });
  await page.getByRole("button", { name: nl("common.cancel") }).click();
  await page.getByTestId(`menu.day.renew.${localDay()}`).click();
  await expect
    .poll(async () => (await admin.from("meal_plan_entries").select("deleted_at").in("id", planned.map((meal) => meal.id))).data?.every((row) => row.deleted_at !== null))
    .toBe(true);
});

// A screen reader on a phone has no long press: the row's menu is also a button after the row, out of sight until it
// has the focus, and Weghalen is in that menu (UNFORGET S46; on iOS VoiceOver reaches the context menu).
test("theRowMenuIsReachableWithoutALongPress", async ({ page }) => {
  let planned: Awaited<ReturnType<typeof todaysMenu>> = [];
  await openMenu(page, async (userID) => {
    planned = await todaysMenu(userID);
  });
  const lunch = planned.find((meal) => meal.slot === "lunch")!;
  const options = page.locator(".swipe-row", { has: page.getByTestId(`menu.entry.${lunch.id}`) }).getByRole("button", { name: nl("menu.entry.options") });
  await options.focus();
  await expect(options).toBeInViewport();
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => violation.id)).toEqual([]);
  await page.keyboard.press("Enter");
  await page.getByRole("alertdialog", { name: lunch.recipe.title }).getByRole("button", { name: nl("menu.remove") }).click();
  await expect(page.getByTestId(`menu.entry.${lunch.id}`)).toHaveCount(0, { timeout: 15_000 });
  const { data } = await admin.from("meal_plan_entries").select("deleted_at").eq("id", lunch.id);
  expect(data?.[0].deleted_at).not.toBeNull();
});

// Another device whose clock runs ahead changed the meal a moment ago: the server takes this tap as older and keeps the
// meal as it was (apply_sync_rules), so the app says it did not work instead of doing nothing, and leaves nothing in
// the diary (UNFORGET S46).
test("aLogTheServerTakesAsOlderSaysSo", async ({ page }) => {
  let planned: Awaited<ReturnType<typeof todaysMenu>> = [];
  const user = await openMenu(page, async (userID) => {
    planned = await todaysMenu(userID);
  });
  const dinner = planned.find((meal) => meal.slot === "dinner")!;
  const ahead = await admin
    .from("meal_plan_entries")
    .update({ updated_at: new Date(Date.now() + 2 * 60_000).toISOString() })
    .eq("id", dinner.id);
  if (ahead.error) throw ahead.error;
  await page.getByTestId(`menu.log.${dinner.id}`).focus();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("alertdialog", { name: nl("error.server") })).toBeVisible({ timeout: 15_000 });
  const { data } = await admin.from("food_entries").select("id").eq("user_id", user.id).is("deleted_at", null);
  expect(data).toEqual([]);
});

// The photo's credit links to the page of the photo, as its licence asks (UNFORGET S46).
test("thePhotoCreditLinksToItsSource", async ({ page }) => {
  let planned: Awaited<ReturnType<typeof todaysMenu>> = [];
  await openMenu(page, async (userID) => {
    planned = await todaysMenu(userID);
  });
  await page.getByTestId(`menu.entry.${planned[0].id}`).click();
  const credit = page.getByRole("link", { name: /Wikimedia Commons/ });
  await expect(credit).toHaveAttribute("href", /^https:\/\/commons\.wikimedia\.org\//);
});
