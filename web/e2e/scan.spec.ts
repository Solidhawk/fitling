import { expect, type Page, test } from "./fixtures";
import { createUser, ean13, nl, sharedProduct, signIn } from "./users";

const lookupProduct = "**/functions/v1/lookup-product";

/** On Vandaag, the scanner open from the log sheet for breakfast. */
async function startScanning(page: Page) {
  const user = await createUser({ profile: true, creature: true });
  await signIn(page, user.email);
  await page.getByTestId("day.add.breakfast").click({ timeout: 15_000 });
  await page.getByTestId("log.scan").click();
  await expect(page.locator('[data-screen="scan"]')).toBeVisible();
}

async function type(page: Page, code: string) {
  await page.getByTestId("scan.manual").fill(code);
  await page.getByTestId("scan.manual.submit").click();
}

// ScanTests on iOS. The camera cannot be driven in CI; the typed code goes the same way.
test("withoutACameraTheCodeCanBeTyped", async ({ page }, info) => {
  await startScanning(page);
  await expect(page.getByText(nl("scan.unavailable"))).toBeVisible();
  await page.screenshot({ path: `test-results/screens/${info.project.name}-scannen.png` });
});

test("scanOfAKnownProductOpensThePortion", async ({ page }) => {
  const gtin = ean13();
  const product = await sharedProduct("Hagelslag", { gtin });
  await startScanning(page);
  let asked = 0;
  await page.route(lookupProduct, (route) => {
    asked += 1;
    return route.continue();
  });
  await type(page, gtin);
  await expect(page.getByTestId("portion.quantity")).toBeVisible();
  await expect(page.locator('[data-page="portion"] .nav-title')).toHaveText(product.name);
  expect(asked).toBe(0);
});

test("scanOfAnUnknownProductOffersToAddIt", async ({ page }) => {
  await startScanning(page);
  await page.route(lookupProduct, (route) => route.fulfill({ status: 404, contentType: "application/json", body: '{"error":"not_found"}' }));
  await type(page, "4006381333931");
  await expect(page.getByRole("alertdialog", { name: nl("scan.unknown.title") })).toBeVisible();
  await page.getByRole("button", { name: nl("scan.unknown.add") }).click();
  await expect(page.getByTestId("product.add.barcode")).toHaveValue("4006381333931");
});

// A misread (a wrong check digit) is not looked up and asks nothing, and the scanner keeps reading: the next code is
// looked up (review of web phase 2: before, the test passed before the app had done anything).
test("misreadIsIgnored", async ({ page }) => {
  await startScanning(page);
  const looked: string[] = [];
  await page.route(lookupProduct, (route) => {
    looked.push(route.request().postData() ?? "");
    return route.fulfill({ status: 404, contentType: "application/json", body: '{"error":"not_found"}' });
  });
  await type(page, "4006381333932");
  await expect(page.getByRole("alertdialog")).toHaveCount(0);
  await expect(page.locator('[data-screen="scan"]')).toBeVisible();
  await type(page, "4006381333931");
  await expect(page.getByRole("alertdialog", { name: nl("scan.unknown.title") })).toBeVisible();
  expect(looked).toHaveLength(1);
  expect(looked[0]).toContain("4006381333931");
});

test("scanWhileOfflineKeepsTheBarcode", async ({ page }) => {
  await startScanning(page);
  await page.route(lookupProduct, (route) => route.abort("internetdisconnected"));
  await type(page, "4006381333931");
  await expect(page.getByRole("alertdialog", { name: nl("common.connection.title") })).toBeVisible();
  await expect(page.getByText(nl("scan.offline.body"))).toBeVisible();
});
