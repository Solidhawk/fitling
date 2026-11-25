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
  // Ticking an item reads the list again, not the supermarkets and their offers (thousands of rows per shop).
  const offerReads: string[] = [];
  const countOfferReads = (request: { url: () => string }) => {
    if (/\/rest\/v1\/(offers|supermarkets|favorite_supermarkets)/.test(request.url())) offerReads.push(request.url());
  };
  page.on("request", countOfferReads);
  await page.getByTestId("shopping.item.Melk").click();
  await expect(page.getByTestId("shopping.item.Melk")).toHaveAttribute("aria-pressed", "true", { timeout: 15_000 });
  page.off("request", countOfferReads);
  expect(offerReads).toEqual([]);
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
  // One line per product and kind of unit, so the same name can stand there twice (grams and pieces).
  const lines = page.getByTestId(`shopping.item.${ingredient}`);
  await expect(lines.first()).toBeVisible({ timeout: 15_000 });
  const sameName = await lines.count();
  const rows = page.locator('[data-testid^="shopping.item."]');
  const count = await rows.count();
  const firstID = await rows.first().getAttribute("data-id");
  // A second time replaces what the menu put there: new rows (new ids), the same lines, not twice.
  await page.getByTestId("shopping.fromMenu").click();
  await expect.poll(() => rows.first().getAttribute("data-id"), { timeout: 15_000 }).not.toBe(firstID);
  await expect(rows).toHaveCount(count);
  await expect(lines).toHaveCount(sameName);
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
  // Named as the user's own list is: after joining, the list of the code is shown all the same.
  const { code } = await sharedList("Boodschappen", "Anna", "Koffie");
  await openShopping(page);
  await page.getByTestId("shopping.invite").click();
  await expect(page.getByRole("alertdialog", { name: nl("shopping.invite.title") })).toContainText(/[0-9A-F]{12}/, { timeout: 15_000 });
  await page.getByRole("button", { name: nl("common.ok"), exact: true }).click();
  await page.getByTestId("shopping.join").click();
  await page.getByTestId("shopping.join.code").fill("000000000000");
  await page.getByTestId("shopping.join.name").fill("Bram");
  await page.getByRole("dialog").getByRole("button", { name: nl("shopping.join.confirm"), exact: true }).click();
  // A wrong code says so, in the sheet where it was typed.
  await expect(page.getByRole("dialog").getByText(nl("shopping.error.invalidInvite"))).toBeVisible({ timeout: 15_000 });
  await page.getByTestId("shopping.join.code").fill(code.toLowerCase());
  await page.screenshot({ path: `test-results/screens/${info.project.name}-meedoen.png` });
  await page.getByRole("dialog").getByRole("button", { name: nl("shopping.join.confirm"), exact: true }).click();
  await expect(page.getByTestId("shopping.item.Koffie")).toBeVisible({ timeout: 15_000 });
  await expect(page.getByTestId("shopping.member")).toHaveText([new RegExp(`Anna\\s*${nl("shopping.owner")}`), "Bram"]);
  // Leaving goes back to the user's own list.
  await page.getByTestId("shopping.leave").click();
  await page.getByRole("alertdialog").getByRole("button", { name: nl("shopping.leave") }).click();
  await expect(page.getByTestId("shopping.item.Koffie")).toHaveCount(0, { timeout: 15_000 });
});
