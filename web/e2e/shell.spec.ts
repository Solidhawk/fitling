import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const tabs = ["Vandaag", "Training", "Menu", "Partner", "Dagdoel"];

test.beforeEach(async ({ page }) => {
  await page.goto("./");
});

test("showsFiveTabs", async ({ page }) => {
  await expect(page.getByRole("tab")).toHaveText(tabs);
  await expect(page.getByRole("tab", { name: "Vandaag" })).toHaveAttribute("aria-selected", "true");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Vandaag");
});

test("switchesTabs", async ({ page }) => {
  await page.getByRole("tab", { name: "Dagdoel" }).click();
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Dagdoel");
  await expect(page.getByRole("tab", { name: "Dagdoel" })).toHaveAttribute("aria-selected", "true");
  await expect(page.getByRole("tab", { name: "Vandaag" })).toHaveAttribute("aria-selected", "false");
});

// The Ground colorset: #EFE9F8 in light, #1B1524 in dark.
test("darkModeUsesDarkTokens", async ({ page }) => {
  const ground = () => page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  await page.emulateMedia({ colorScheme: "light" });
  expect(await ground()).toBe("rgb(239, 233, 248)");
  await page.emulateMedia({ colorScheme: "dark" });
  expect(await ground()).toBe("rgb(27, 21, 36)");
});

// On an iPhone from the home screen the bar sits above the home indicator. A desktop browser resolves
// env() to 0, so the rule itself is checked.
test("tabBarRespectsSafeArea", async ({ page }) => {
  const usesInset = await page.evaluate(() => {
    const bar = document.querySelector('[role="tablist"]');
    if (!bar) return false;
    return [...document.styleSheets].some((sheet) =>
      [...sheet.cssRules].some(
        (rule) => rule instanceof CSSStyleRule && bar.matches(rule.selectorText) && rule.style.paddingBottom.includes("safe-area-inset-bottom"),
      ),
    );
  });
  expect(usesInset).toBe(true);
});

test("tabsAreBigEnough", async ({ page }) => {
  for (const tab of await page.getByRole("tab").all()) {
    const box = await tab.boundingBox();
    expect(box?.width).toBeGreaterThanOrEqual(44);
    expect(box?.height).toBeGreaterThanOrEqual(44);
  }
});

for (const scheme of ["light", "dark"] as const) {
  test(`noAccessibilityViolations ${scheme}`, async ({ page }) => {
    await page.emulateMedia({ colorScheme: scheme });
    for (const name of tabs) {
      await page.getByRole("tab", { name }).click();
      const result = await new AxeBuilder({ page }).analyze();
      expect(result.violations.map((violation) => `${name}: ${violation.id}`)).toEqual([]);
    }
  });

  test(`screenshots ${scheme}`, async ({ page }, info) => {
    await page.emulateMedia({ colorScheme: scheme });
    for (const name of tabs) {
      await page.getByRole("tab", { name }).click();
      await page.screenshot({ path: `test-results/screens/${info.project.name}-${name.toLowerCase()}-${scheme === "light" ? "licht" : "donker"}.png` });
    }
  });
}
