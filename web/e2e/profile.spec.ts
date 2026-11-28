import { readFile } from "node:fs/promises";
import AxeBuilder from "@axe-core/playwright";
import type { Download } from "@playwright/test";
import { expect, type Page, test } from "./fixtures";
import { admin, createUser, nl, signIn } from "./users";

/** Signed in with the profile of NutritionEngineTests (2760 kcal) and a partner, on the Dagdoel tab. */
async function start(page: Page) {
  const user = await createUser({ profile: true, creature: true });
  await signIn(page, user.email);
  await page.getByRole("tab", { name: nl("profile.title") }).click();
  // The first visit also loads the rules (WebAssembly); WebKit on a busy CI machine needs more than 5 s for that.
  await expect(page.getByTestId("profile.target")).toBeVisible({ timeout: 15_000 });
  return user;
}

// Back on Dagdoel, after another device changed the target or a new day began: the screen reads it again
// (UNFORGET S53).
test("backOnDagdoelShowsTheTargetOfNow", async ({ page }) => {
  const user = await start(page);
  await expect(page.getByTestId("profile.target")).toHaveText(/2\.760\s?kcal/);
  const { error } = await admin.from("profiles").update({ kcal_target: 2400, targets_are_manual: true, updated_at: new Date().toISOString() })
    .eq("id", user.id);
  expect(error).toBeNull();
  await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
  await expect(page.getByTestId("profile.target")).toHaveText(/2\.400\s?kcal/, { timeout: 15_000 });
});

// A target saved here, then the connection drops: back on Dagdoel, what this browser keeps for offline is the saved
// target, not the one read before (UNFORGET S53, review).
test("aSavedTargetStaysWhenTheConnectionDrops", async ({ page, context }) => {
  await start(page);
  await adjust(page, "profile.editTargets");
  await page.getByTestId("input.target.kcal").fill("2500");
  await page.getByTestId("input.target.proteinG").fill("150");
  await page.getByTestId("input.target.carbsG").fill("300");
  await page.getByTestId("input.target.fatG").fill("70");
  await page.getByRole("button", { name: nl("profile.save") }).click();
  await expect(page.getByTestId("profile.target")).toHaveText(/2\.500\s?kcal/);
  await context.setOffline(true);
  await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
  // Room for a read from this browser's copy to land before looking.
  await page.waitForTimeout(1000);
  await expect(page.getByTestId("profile.target")).toHaveText(/2\.500\s?kcal/);
  await context.setOffline(false);
});

async function shot(page: Page, name: string, project: string) {
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => `${name}: ${violation.id}`)).toEqual([]);
  await page.screenshot({ path: `test-results/screens/${project}-dagdoel-${name}.png`, fullPage: true });
}

async function adjust(page: Page, item: string) {
  await page.getByTestId("profile.adjust").click();
  await page.getByRole("menuitem", { name: nl(item) }).click();
}

// 30 years, male, 180 cm, 80 kg, moderately active, maintain: BMR 1780, TDEE 2759, target 2760.
test("Dagdoel shows how 2760 kcal is built and the macros", async ({ page }, info) => {
  await start(page);
  await expect(page.getByTestId("profile.target")).toHaveText(/2\.760\s?kcal/);
  await expect(page.getByText(/1\.780\s?kcal/)).toBeVisible();
  await expect(page.getByText(/2\.759\s?kcal/)).toBeVisible();
  await expect(page.getByText(nl("profile.buildUp.activity %@").replace("%@", "1,55"))).toBeVisible();
  await expect(page.getByText(nl("profile.buildUp.goal %@").replace("%@", "100%"))).toBeVisible();
  for (const grams of ["128", "389", "77"]) await expect(page.getByText(new RegExp(`^${grams}\\s?g$`))).toBeVisible();
  await expect(page.getByTestId("profile.proteinPerKg")).toHaveText(nl("profile.proteinPerKg.value %@").replace("%@", "1,6"));
  await shot(page, "1-opbouw", info.project.name);
});

// ProfileViewModelTests.saveTargetsMarksManualAndPending and changingTargetsTwiceOnOneDayKeepsOnePeriod.
test("ownTargetsAreSavedAndKeepOnePeriodToday", async ({ page }, info) => {
  const user = await start(page);
  await adjust(page, "profile.editTargets");
  await shot(page, "2-doelen", info.project.name);
  await page.getByTestId("input.target.kcal").fill("2500");
  await page.getByTestId("input.target.proteinG").fill("150");
  await page.getByTestId("input.target.carbsG").fill("300");
  await page.getByTestId("input.target.fatG").fill("70");
  await page.getByRole("button", { name: nl("profile.save") }).click();
  await expect(page.getByTestId("profile.target")).toHaveText(/2\.500\s?kcal/);
  await expect(page.getByText(nl("profile.targets.manual"))).toBeVisible();
  const { data: profile } = await admin.from("profiles").select("kcal_target, protein_target_g, targets_are_manual").eq("id", user.id).single();
  expect(profile).toEqual({ kcal_target: 2500, protein_target_g: 150, targets_are_manual: true });
  const { data: periods } = await admin.from("target_history").select("kcal_target").eq("user_id", user.id);
  expect(periods).toEqual([{ kcal_target: 2500 }]);
});

// ProfileViewModelTests.saveTargetsOutOfRangeThrows: the value is pointed out and nothing is saved.
test("aTargetOutOfRangeIsNotSaved", async ({ page }) => {
  const user = await start(page);
  await adjust(page, "profile.editTargets");
  await page.getByTestId("input.target.kcal").fill("0");
  await page.getByRole("button", { name: nl("profile.save") }).click();
  await expect(page.getByText(nl("profile.targets.outOfRange"))).toBeVisible();
  const { data } = await admin.from("profiles").select("kcal_target").eq("id", user.id).single();
  expect(data).toEqual({ kcal_target: 2760 });
});

// ProfileViewModelTests.editingProfileRecalculatesAutoTargets and editingProfileWithManualTargetsAsks.
test("editingTheProfileFollowsThePlanAndAsksAboutOwnTargets", async ({ page }, info) => {
  const user = await start(page);
  await adjust(page, "profile.edit");
  await shot(page, "3-profiel", info.project.name);
  await page.getByTestId("input.weight").fill("90");
  await page.getByRole("button", { name: nl("profile.save") }).click();
  await expect(page.getByTestId("profile.target")).not.toHaveText(/2\.760\s?kcal/);
  const { data: following } = await admin.from("profiles").select("weight_kg, kcal_target").eq("id", user.id).single();
  expect(following?.weight_kg).toBe(90);
  expect(following?.kcal_target).not.toBe(2760);

  await admin.from("profiles").update({ targets_are_manual: true, kcal_target: 2500 }).eq("id", user.id);
  await page.reload();
  await page.getByRole("tab", { name: nl("profile.title") }).click();
  await adjust(page, "profile.edit");
  await page.getByTestId("input.weight").fill("85");
  await page.getByRole("button", { name: nl("profile.save") }).click();
  await expect(page.getByRole("alertdialog", { name: nl("profile.recalculate.title") })).toBeVisible();
  await page.getByRole("button", { name: nl("profile.recalculate.keep") }).click();
  await expect(page.getByTestId("profile.target")).toHaveText(/2\.500\s?kcal/);
});

// AccountView: one JSON file with every table, the profile among them.
test("exportGivesAFileWithTheProfile", async ({ page }) => {
  // The share sheet cannot be driven in a test; without it the files are downloaded, as on a desktop.
  await page.addInitScript(() => Object.defineProperty(navigator, "canShare", { value: undefined }));
  const user = await start(page);
  await page.getByRole("button", { name: nl("account.title") }).click();
  // One download per file, in an order the browser chooses (WebKit starts with a CSV file).
  const download = new Promise<Download>((resolve) => {
    page.on("download", (file) => {
      if (file.suggestedFilename() === "fitling-export.json") resolve(file);
    });
  });
  await page.getByRole("button", { name: nl("account.export") }).click();
  const file = await download;
  const exported = JSON.parse(await readFile((await file.path())!, "utf8"));
  expect(exported.tables.profiles).toEqual([expect.objectContaining({ id: user.id, kcal_target: 2760 })]);
  expect(exported.tables.creatures).toEqual([expect.objectContaining({ species: "owl", name: "Uiltje" })]);
});

test("deletingTheAccountLeadsToWelcome", async ({ page }, info) => {
  const user = await start(page);
  await page.getByRole("button", { name: nl("account.title") }).click();
  await page.getByRole("button", { name: nl("account.delete") }).click();
  await shot(page, "4-verwijderen", info.project.name);
  await page.getByRole("button", { name: nl("account.delete.confirm") }).click();
  await expect(page.getByRole("alertdialog", { name: nl("account.delete") })).toBeVisible();
  // A screen reader hears what the alert says, not only its title (review of web phase 2).
  await expect(page.getByRole("alertdialog", { name: nl("account.delete") })).toHaveAccessibleDescription(nl("account.delete.body"));
  await page.getByRole("alertdialog").getByRole("button", { name: nl("account.delete.confirm") }).click();
  await expect(page.locator('[data-screen="welcome"]')).toBeAttached();
  const { data } = await admin.auth.admin.getUserById(user.id);
  expect(data.user).toBeNull();
});

// Signing out in a second tab closes the first one too, without leaving half a screen (plan Task 3).
test("signedOutElsewhereReturnsToWelcome", async ({ page, context }) => {
  await start(page);
  const other = await context.newPage();
  await other.goto("./");
  await other.getByRole("tab", { name: nl("profile.title") }).click();
  await other.getByRole("button", { name: nl("account.title") }).click();
  await other.getByRole("button", { name: nl("account.signOut") }).click();
  await expect(other.locator('[data-screen="welcome"]')).toBeAttached();
  await expect(page.locator('[data-screen="welcome"]')).toBeAttached();
});

test("swipingBackLeavesAccountForDagdoel", async ({ page }) => {
  await start(page);
  await page.getByRole("button", { name: nl("account.title") }).click();
  await page.getByRole("button", { name: nl("account.about") }).click();
  await expect(page.locator('[data-page="about"]')).toBeVisible();
  await page.goBack();
  await expect(page.locator('[data-page="account"]')).toBeVisible();
  await page.goBack();
  await expect(page.getByTestId("profile.target")).toBeVisible();
});

// The terms of NEVO ask for its source and version wherever its data is used (UNFORGET S15).
test("aboutNamesNevo", async ({ page }) => {
  await start(page);
  await page.getByRole("button", { name: nl("account.title") }).click();
  await page.getByRole("button", { name: nl("account.about") }).click();
  await expect(page.locator('[data-page="about"]')).toContainText("NEVO-online versie 2025/9.0, RIVM, Bilthoven");
  const link = page.getByRole("link", { name: nl("account.about.website %@").replace("%@", "NEVO-online") });
  await expect(link).toHaveAttribute("href", "https://nevo-online.rivm.nl");
});

test.describe("in the United States", () => {
  test.use({ locale: "en-US" });

  // BodyInput keeps the stored value while the fields are unchanged: 180 cm shown as 5 ft 10.9 in stays 180 cm.
  test("savingTheProfileUnchangedKeepsTheHeight", async ({ page }) => {
    const user = await createUser({ profile: true, creature: true });
    await signIn(page, user.email);
    await page.getByRole("tab").nth(4).click();
    await expect(page.getByTestId("profile.target")).toBeVisible({ timeout: 15_000 });
    await page.getByTestId("profile.adjust").click();
    await page.getByRole("menuitem").first().click();
    await expect(page.getByTestId("input.inches")).toHaveValue("10.9");
    await page.locator(".nav-confirm").click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
    const { data } = await admin.from("profiles").select("height_cm, kcal_target").eq("id", user.id).single();
    expect(data).toEqual({ height_cm: 180, kcal_target: 2760 });
    const { data: periods } = await admin.from("target_history").select("id").eq("user_id", user.id);
    expect(periods).toHaveLength(1);
  });
});

// A sheet keeps the keyboard inside it, closes on Escape and gives the focus back to Aanpassen.
test("aSheetKeepsTheFocusAndGivesItBack", async ({ page }) => {
  await start(page);
  await page.getByTestId("profile.adjust").click();
  await page.getByRole("menuitem", { name: nl("profile.editTargets") }).click();
  const inside = () => page.evaluate(() => document.activeElement?.closest('[role="dialog"]') !== null);
  expect(await inside()).toBe(true);
  for (let press = 0; press < 12; press++) await page.keyboard.press("Tab");
  expect(await inside()).toBe(true);
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(page.getByTestId("profile.adjust")).toBeFocused();
});
