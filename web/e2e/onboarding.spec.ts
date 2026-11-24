import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "./fixtures";
import { admin, createUser, nl, signIn } from "./users";

async function start(page: Page) {
  const user = await createUser();
  await signIn(page, user.email);
  await expect(page.getByTestId("onboarding.step.consent")).toBeVisible();
  return user;
}

async function next(page: Page, step: string) {
  await page.getByTestId(`onboarding.continue.${step}`).click();
}

async function shot(page: Page, name: string, project: string) {
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => `${name}: ${violation.id}`)).toEqual([]);
  await page.screenshot({ path: `test-results/screens/${project}-onboarding-${name}.png` });
}

/** The profile of OnboardingFlowTests: 30 years, male, 180 cm, 80 kg, moderately active, maintain: 2760 kcal. */
test("the whole onboarding gives the app's targets and leads to choosing a partner", async ({ page }, info) => {
  const user = await start(page);
  await shot(page, "1-toestemming", info.project.name);
  await expect(page.getByTestId("onboarding.continue.consent")).toBeDisabled();
  await page.getByTestId("consent.agree").check();
  await next(page, "consent");
  await shot(page, "2-geboortedatum", info.project.name);
  await next(page, "birthDate");
  await page.getByRole("radio", { name: nl("onboarding.sex.male") }).click();
  await shot(page, "3-geslacht", info.project.name);
  await next(page, "sex");
  await page.getByTestId("input.height").fill("180");
  await shot(page, "4-lengte", info.project.name);
  await next(page, "height");
  await page.getByTestId("input.weight").fill("80");
  await next(page, "weight");
  await page.getByRole("radio", { name: new RegExp(nl("onboarding.activity.moderate")) }).click();
  await shot(page, "6-activiteit", info.project.name);
  await next(page, "activity");
  await page.getByRole("radio", { name: new RegExp(nl("onboarding.goal.maintain")) }).click();
  await shot(page, "7-doel", info.project.name);
  await next(page, "goal");
  await expect(page.getByTestId("targets.kcal")).toHaveText(/2\.760\s?kcal/);
  await expect(page.getByText(/128\s?g/)).toBeVisible();
  await shot(page, "8-resultaat", info.project.name);
  await next(page, "result");
  await expect(page.locator('[data-screen="partnerSetup"]')).toBeAttached();
  const { data } = await admin.from("profiles").select("kcal_target, height_cm, weight_kg, goal").eq("id", user.id).single();
  expect(data).toEqual({ kcal_target: 2760, height_cm: 180, weight_kg: 80, goal: "maintain" });
});

test("underageCannotContinue", async ({ page }) => {
  await start(page);
  await page.getByTestId("consent.agree").check();
  await next(page, "consent");
  await page.getByTestId("input.birthDate").fill("2015-01-01");
  await expect(page.getByTestId("onboarding.continue.birthDate")).toHaveCount(0);
  await expect(page.getByText(nl("onboarding.underage.body"))).toBeVisible();
  await expect(page.getByRole("button", { name: nl("onboarding.underage.delete") })).toBeVisible();
});

// AppFlowTests.underageDeletionClosesWhenSignedOut: the account goes, the app shows Welcome.
test("underageDeletionLeadsToWelcome", async ({ page }) => {
  const user = await start(page);
  await page.getByTestId("consent.agree").check();
  await next(page, "consent");
  await page.getByTestId("input.birthDate").fill("2015-01-01");
  await page.getByRole("button", { name: nl("onboarding.underage.delete") }).click();
  await expect(page.locator('[data-screen="welcome"]')).toBeAttached();
  const { data } = await admin.auth.admin.getUserById(user.id);
  expect(data.user).toBeNull();
});

test("saveFailureShowsServerError", async ({ page }) => {
  const user = await start(page);
  await page.getByTestId("consent.agree").check();
  await next(page, "consent");
  await next(page, "birthDate");
  await page.getByRole("radio", { name: nl("onboarding.sex.female") }).click();
  await next(page, "sex");
  await page.getByTestId("input.height").fill("170");
  await next(page, "height");
  await page.getByTestId("input.weight").fill("65");
  await next(page, "weight");
  await page.getByRole("radio", { name: new RegExp(nl("onboarding.activity.light")) }).click();
  await next(page, "activity");
  await page.getByRole("radio", { name: new RegExp(nl("onboarding.goal.lose")) }).click();
  await next(page, "goal");
  await page.route("**/rest/v1/target_history*", (route) => route.abort());
  await next(page, "result");
  await expect(page.getByRole("alertdialog", { name: nl("error.server") })).toBeVisible();
  const { data } = await admin.from("profiles").select("id").eq("id", user.id).maybeSingle();
  expect(data).toBeNull();
});

test.describe("in the United States", () => {
  test.use({ locale: "en-US" });

  test("imperialUnitsGiveTheSameProfile", async ({ page }) => {
    const user = await start(page);
    await page.getByTestId("consent.agree").check();
    await next(page, "consent");
    await next(page, "birthDate");
    await page.getByRole("radio").first().click();
    await next(page, "sex");
    await page.getByTestId("input.feet").fill("5");
    await page.getByTestId("input.inches").fill("11");
    await next(page, "height");
    await page.getByTestId("input.weight").fill("176");
    await next(page, "weight");
    await page.getByRole("radio").nth(2).click();
    await next(page, "activity");
    await page.getByRole("radio").nth(2).click();
    await next(page, "goal");
    await next(page, "result");
    await expect(page.locator('[data-screen="partnerSetup"]')).toBeAttached();
    const { data } = await admin.from("profiles").select("height_cm, weight_kg").eq("id", user.id).single();
    expect(data).toEqual({ height_cm: 180.3, weight_kg: 79.8 });
  });
});
