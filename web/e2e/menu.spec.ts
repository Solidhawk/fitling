import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "./fixtures";
import { openMenu, sharedRecipe, todaysMenu } from "./menu";
import { admin, localDay, nl, nlCount } from "./users";

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
  // The next menu opens with these choices.
  await page.getByTestId("menu.generate").click();
  await expect(page.getByTestId("menu.generator.days")).toContainText(nlCount("menu.generator.days %lld", 5));
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

test("preferencesAreSavedAtOnce", async ({ page }) => {
  const user = await openMenu(page);
  await page.getByTestId("menu.preferences").click();
  await page.getByTestId("menu.prefs.tag.fish").check();
  await page.getByTestId("menu.prefs.slot.breakfast").uncheck();
  await page.getByRole("button", { name: nl("common.ok"), exact: true }).click();
  await expect
    .poll(async () => (await admin.from("menu_preferences").select("excluded_tags, meal_slots").eq("user_id", user.id)).data)
    .toEqual([{ excluded_tags: ["fish"], meal_slots: ["lunch", "dinner"] }]);
});
