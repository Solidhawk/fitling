import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "./fixtures";
import { todaysMenu } from "./menu";
import { openShopping, sharedList, shopWithOffers } from "./shopping";
import { admin, nl } from "./users";

// ShoppingTests and the shopping UI tests on iOS: the list, the menu, offers and sharing (web phase 6).

test("addingCheckingAndClearing", async ({ page }, info) => {
  const user = await openShopping(page);
  await expect(page.getByText(nl("shopping.empty"))).toBeVisible();
  await page.getByTestId("shopping.add.field").fill("  Melk ");
  await page.keyboard.press("Enter");
  await page.getByTestId("shopping.add.field").fill("Brood");
  await page.getByRole("button", { name: nl("shopping.add"), exact: true }).click();
  await expect(page.getByTestId("shopping.item.Melk")).toBeVisible({ timeout: 15_000 });
  await expect(page.getByTestId("shopping.item.Brood")).toBeVisible({ timeout: 15_000 });
  // Nothing to add while the field is empty.
  await expect(page.getByRole("button", { name: nl("shopping.add"), exact: true })).toBeDisabled();
  await page.getByTestId("shopping.item.Melk").click();
  await expect(page.getByTestId("shopping.item.Melk")).toHaveAttribute("aria-pressed", "true", { timeout: 15_000 });
  await page.screenshot({ path: `test-results/screens/${info.project.name}-boodschappen.png`, fullPage: true });
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => violation.id)).toEqual([]);
  await page.getByTestId("shopping.clearChecked").click();
  await expect(page.getByTestId("shopping.item.Melk")).toHaveCount(0, { timeout: 15_000 });
  const { data } = await admin.from("shopping_items").select("name, deleted_at, updated_by").order("name");
  expect(data?.filter((row) => row.updated_by === user.id).map((row) => [row.name, row.deleted_at !== null])).toEqual([
    ["Brood", false],
    ["Melk", true],
  ]);
});

test("theMenuFillsTheList", async ({ page }) => {
  let planned: Awaited<ReturnType<typeof todaysMenu>> = [];
  await openShopping(page, async (userID) => {
    planned = await todaysMenu(userID);
  });
  const { data } = await admin.from("recipe_ingredients").select("name").eq("recipe_id", planned[2].recipe.id).order("position").limit(1);
  const ingredient = (data![0].name as { nl: string }).nl;
  await page.getByTestId("shopping.fromMenu").click();
  await expect(page.getByTestId(`shopping.item.${ingredient}`)).toBeVisible({ timeout: 15_000 });
  const count = await page.locator('[data-testid^="shopping.item."]').count();
  // A second time replaces what the menu put there: the same lines, not twice.
  await page.getByTestId("shopping.fromMenu").click();
  await expect(page.getByTestId(`shopping.item.${ingredient}`)).toHaveCount(1, { timeout: 15_000 });
  await expect(page.locator('[data-testid^="shopping.item."]')).toHaveCount(count);
});

test("offersShowWithTheirValidity", async ({ page }, info) => {
  const shop = await shopWithOffers("Proefmarkt", [
    { title: "Halfvolle melk 1 l", cents: 99 },
    { title: "Tomatenblokjes 400 g", cents: 69 },
  ]);
  await openShopping(page);
  for (const name of ["Halfvolle melk", "Tomaat"]) {
    await page.getByTestId("shopping.add.field").fill(name);
    await page.keyboard.press("Enter");
    await expect(page.getByTestId(`shopping.item.${name}`)).toBeVisible({ timeout: 15_000 });
  }
  await page.getByTestId("shopping.shops").click();
  await page.getByTestId(`shopping.shop.${shop}`).check();
  await page.getByRole("button", { name: nl("common.ok"), exact: true }).click();
  // The same words: a price at once, with its shop and its last day.
  const offer = page.getByTestId("shopping.offer.Halfvolle melk");
  await expect(offer).toContainText(/0,99/, { timeout: 15_000 });
  await expect(offer).toContainText("Proefmarkt");
  await expect(offer).toContainText("t/m");
  await expect(page.getByTestId(`shopping.total.${shop}`)).toContainText(/0,99/);
  // Possibly the same: asked first, counted after "Klopt".
  await expect(page.getByTestId("shopping.offer.Tomaat")).toHaveCount(0);
  await expect(page.getByTestId("shopping.question")).toContainText("Tomatenblokjes 400 g");
  await page.screenshot({ path: `test-results/screens/${info.project.name}-aanbiedingen.png`, fullPage: true });
  await page.getByTestId("shopping.question").getByRole("button", { name: nl("shopping.confirm") }).click();
  await expect(page.getByTestId("shopping.offer.Tomaat")).toContainText(/0,69/);
  await expect(page.getByTestId(`shopping.total.${shop}`)).toContainText(/1,68/);
  await expect(page.getByTestId("shopping.question")).toHaveCount(0);
});

test("inviteAndJoin", async ({ page }, info) => {
  // A list that sorts before the user's own, so it is the one shown after joining (ShoppingStore.lists()).
  const { code } = await sharedList("Alles in huis", "Anna", "Koffie");
  await openShopping(page);
  await page.getByTestId("shopping.invite").click();
  await expect(page.getByRole("alertdialog", { name: nl("shopping.invite.title") })).toContainText(/[0-9A-F]{12}/, { timeout: 15_000 });
  await page.getByRole("button", { name: nl("common.ok"), exact: true }).click();
  await page.getByTestId("shopping.join").click();
  await page.getByTestId("shopping.join.code").fill("000000000000");
  await page.getByTestId("shopping.join.name").fill("Bram");
  await page.getByRole("button", { name: nl("shopping.join.confirm") }).click();
  // A wrong code says so, under the members.
  await expect(page.getByText(nl("shopping.error.invalidInvite"))).toBeVisible({ timeout: 15_000 });
  await page.getByTestId("shopping.join.code").fill(code.toLowerCase());
  await page.screenshot({ path: `test-results/screens/${info.project.name}-meedoen.png` });
  await page.getByRole("button", { name: nl("shopping.join.confirm") }).click();
  await expect(page.getByRole("heading", { name: "Alles in huis" })).toBeVisible({ timeout: 15_000 });
  await expect(page.getByTestId("shopping.item.Koffie")).toBeVisible();
  await expect(page.getByTestId("shopping.member")).toHaveText([new RegExp(`Anna\\s*${nl("shopping.owner")}`), "Bram"]);
  // Leaving goes back to the user's own list.
  await page.getByTestId("shopping.leave").click();
  await page.getByRole("alertdialog").getByRole("button", { name: nl("shopping.leave") }).click();
  await expect(page.getByTestId("shopping.item.Koffie")).toHaveCount(0, { timeout: 15_000 });
});
