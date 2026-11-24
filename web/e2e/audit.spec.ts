import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "./fixtures";
import { createUser, nl, signIn } from "./users";

// Every screen of phase 1 in light, dark and at 200 % text (the largest text on iOS is about that): no axe
// violations, and at 200 % nothing that only a sideways scroll reaches. The screenshots go on the board next to iOS.
const modes = ["licht", "donker", "groot"] as const;
type Mode = (typeof modes)[number];

async function prepare(page: Page, mode: Mode) {
  if (mode === "donker") await page.emulateMedia({ colorScheme: "dark" });
  if (mode === "groot") {
    await page.addInitScript(() => {
      document.addEventListener("DOMContentLoaded", () => {
        const style = document.createElement("style");
        style.textContent = "html { font-size: 200%; }";
        document.head.append(style);
      });
    });
  }
}

async function check(page: Page, mode: Mode, name: string, project: string) {
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => `${mode} ${name}: ${violation.id}`)).toEqual([]);
  if (mode === "groot") {
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow, `${name} scrolls sideways at 200 %`).toBeLessThanOrEqual(0);
  }
  await page.screenshot({ path: `test-results/screens/${project}-audit-${mode}-${name}.png` });
}

for (const mode of modes) {
  test.describe(mode, () => {
    test.beforeEach(({ page }) => prepare(page, mode));

    test("welcome and email", async ({ page }, info) => {
      await page.goto("./");
      await expect(page.getByTestId("welcome.email")).toBeVisible();
      await check(page, mode, "0-welkom", info.project.name);
      await page.getByTestId("welcome.email").click();
      await expect(page.locator('input[type="email"]')).toBeVisible();
      await check(page, mode, "0-email", info.project.name);
    });

    test("onboarding", async ({ page }, info) => {
      const user = await createUser();
      await signIn(page, user.email);
      const step = async (name: string, number: string, act: () => Promise<void>) => {
        await expect(page.getByTestId(`onboarding.step.${name}`)).toBeVisible();
        await act();
        await check(page, mode, `${number}-${name}`, info.project.name);
        await page.getByTestId(`onboarding.continue.${name}`).click();
      };
      await step("consent", "1", () => page.getByTestId("consent.agree").check());
      await step("birthDate", "2", async () => {});
      await step("sex", "3", () => page.getByRole("radio", { name: nl("onboarding.sex.male") }).click());
      await step("height", "4", () => page.getByTestId("input.height").fill("180"));
      await step("weight", "5", () => page.getByTestId("input.weight").fill("80"));
      await step("activity", "6", () => page.getByRole("radio", { name: new RegExp(nl("onboarding.activity.moderate")) }).click());
      await step("goal", "7", () => page.getByRole("radio", { name: new RegExp(nl("onboarding.goal.maintain")) }).click());
      await expect(page.getByTestId("targets.kcal")).toBeVisible();
      await check(page, mode, "8-result", info.project.name);
    });

    test("partner", async ({ page }, info) => {
      const user = await createUser({ profile: true });
      await signIn(page, user.email);
      await expect(page.getByTestId("partner.setup.species.owl")).toBeVisible();
      await check(page, mode, "9-partner", info.project.name);
      await page.getByTestId("partner.setup.species.owl").click();
      await page.getByTestId("partner.setup.name").scrollIntoViewIfNeeded();
      await check(page, mode, "10-partner-naam", info.project.name);
    });

    test("Dagdoel and account", async ({ page }, info) => {
      const user = await createUser({ profile: true, creature: true });
      await signIn(page, user.email);
      await page.getByRole("tab", { name: nl("profile.title") }).click();
      await expect(page.getByTestId("profile.target")).toBeVisible();
      await check(page, mode, "13-dagdoel", info.project.name);
      await page.getByTestId("profile.adjust").click();
      await expect(page.getByRole("menu")).toBeVisible();
      await check(page, mode, "14-aanpassen", info.project.name);
      await page.getByRole("menuitem", { name: nl("profile.edit") }).click();
      await check(page, mode, "15-profiel", info.project.name);
      await page.getByRole("button", { name: nl("common.cancel") }).click();
      await page.getByTestId("profile.adjust").click();
      await page.getByRole("menuitem", { name: nl("profile.editTargets") }).click();
      await check(page, mode, "16-doelen", info.project.name);
      await page.getByRole("button", { name: nl("common.cancel") }).click();
      await page.getByRole("button", { name: nl("account.title") }).click();
      await check(page, mode, "17-account", info.project.name);
      await page.getByRole("button", { name: nl("account.about") }).click();
      await check(page, mode, "18-over", info.project.name);
      await page.goBack();
      await page.getByRole("button", { name: nl("account.delete") }).click();
      await check(page, mode, "19-verwijderen", info.project.name);
    });
  });
}
