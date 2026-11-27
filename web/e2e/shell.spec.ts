import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "./fixtures";
import { createUser, nl, password, signIn } from "./users";

const tabs = ["Vandaag", "Training", "Menu", "Partner", "Dagdoel"];

// The tabs are there once signed in with a profile and a partner.
test.beforeEach(async ({ page }) => {
  const user = await createUser({ profile: true, creature: true });
  await signIn(page, user.email);
  await expect(page.locator('[data-screen="home"]')).toBeAttached();
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

// The Ground colorset: #EFE9F8 in light, #1B1524 in dark; the Ink colorset, the text: #231A33 and #F6F2FC.
test("darkModeUsesDarkTokens", async ({ page }) => {
  const ground = () => page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  const ink = () => page.evaluate(() => getComputedStyle(document.body).color);
  await page.emulateMedia({ colorScheme: "light" });
  expect(await ground()).toBe("rgb(239, 233, 248)");
  expect(await ink()).toBe("rgb(35, 26, 51)");
  await page.emulateMedia({ colorScheme: "dark" });
  expect(await ground()).toBe("rgb(27, 21, 36)");
  expect(await ink()).toBe("rgb(246, 242, 252)");
});

// The tab bar as a tablist (WAI-ARIA tabs): the arrow keys go to the next tab and open it, Home and End to the first
// and the last, and Tab reaches only the open one (UNFORGET S36).
test("arrowKeysMoveBetweenTheTabs", async ({ page }) => {
  const tab = (name: string) => page.getByRole("tab", { name });
  await tab("Vandaag").focus();
  await page.keyboard.press("ArrowRight");
  await expect(tab("Training")).toBeFocused();
  await expect(tab("Training")).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("End");
  await expect(tab("Dagdoel")).toBeFocused();
  await page.keyboard.press("ArrowRight");
  await expect(tab("Vandaag")).toBeFocused();
  await page.keyboard.press("ArrowLeft");
  await expect(tab("Dagdoel")).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("Home");
  await expect(tab("Vandaag")).toHaveAttribute("aria-selected", "true");
  await expect(tab("Vandaag")).toHaveAttribute("tabindex", "0");
  await expect(tab("Training")).toHaveAttribute("tabindex", "-1");
  // With a modifier the arrow is the browser's or the system's (Alt+Left is Back), not a tab key (review of PR #60).
  await page.keyboard.press("Control+ArrowRight");
  await expect(tab("Vandaag")).toHaveAttribute("aria-selected", "true");
});

// A reload opens the tab that was open, as the address says; switching tabs adds nothing to the history, so Back
// still leaves the app as before (UNFORGET S36).
test("aReloadKeepsTheTab", async ({ page }) => {
  const entries = await page.evaluate(() => history.length);
  await page.getByRole("tab", { name: "Menu" }).click();
  await page.getByRole("tab", { name: "Partner" }).click();
  expect(await page.evaluate(() => history.length)).toBe(entries);
  await page.reload();
  await expect(page.getByRole("tab", { name: "Partner" })).toHaveAttribute("aria-selected", "true", { timeout: 15_000 });
});

// A session ends with its tab: signing in again in this browser tab opens on Vandaag, not on the tab the session before
// was on (review of PR #60).
test("aNewSessionOpensOnVandaag", async ({ page }) => {
  await page.getByRole("tab", { name: "Dagdoel" }).click();
  await page.getByRole("button", { name: nl("account.title") }).click();
  await page.getByRole("button", { name: nl("account.signOut") }).click();
  await expect(page.locator('[data-screen="welcome"]')).toBeAttached();
  const user = await createUser({ profile: true, creature: true });
  await page.getByTestId("welcome.email").click();
  await page.locator('input[type="email"]').fill(user.email);
  await page.locator('input[type="password"]').fill(password);
  await page.getByTestId("auth.submit").click();
  await expect(page.getByRole("tab", { name: "Vandaag" })).toHaveAttribute("aria-selected", "true", { timeout: 15_000 });
  expect(await page.evaluate(() => location.hash)).not.toBe("#target");
});

// Turned sideways, an iPhone's notch is at a side: the page, the tab bar and sheets keep clear of it. A desktop browser
// resolves env() to 0, so the rules themselves are checked (UNFORGET S36).
test("theScreenKeepsClearOfTheNotchSideways", async ({ page }) => {
  const clear = await page.evaluate(() => {
    const rules = [...document.styleSheets].flatMap((sheet) => [...sheet.cssRules]).filter((rule) => rule instanceof CSSStyleRule);
    const keepsClear = (selector: string) =>
      rules.some(
        (rule) =>
          rule.selectorText === selector &&
          rule.style.paddingLeft.includes("safe-area-inset-left") &&
          rule.style.paddingRight.includes("safe-area-inset-right"),
      );
    return { page: keepsClear(".page"), tabBar: keepsClear(".tab-bar-frame"), sheet: keepsClear(".sheet") };
  });
  expect(clear).toEqual({ page: true, tabBar: true, sheet: true });
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
    // Five tabs, each checked in full: more than the default 30 s on a busy runner (WebKit, CI run 45695264777).
    test.setTimeout(90_000);
    await page.emulateMedia({ colorScheme: scheme });
    for (const name of tabs) {
      await page.getByRole("tab", { name }).click();
      const result = await new AxeBuilder({ page }).analyze();
      expect(result.violations.map((violation) => `${name}: ${violation.id}`)).toEqual([]);
    }
  });

  test(`screenshots ${scheme}`, async ({ page }, info) => {
    // Five tabs, each drawn in full: more than the default 30 s on a busy runner (WebKit, CI run 45707606229).
    test.setTimeout(90_000);
    await page.emulateMedia({ colorScheme: scheme });
    for (const name of tabs) {
      await page.getByRole("tab", { name }).click();
      await page.screenshot({ path: `test-results/screens/${info.project.name}-${name.toLowerCase()}-${scheme === "light" ? "licht" : "donker"}.png` });
    }
  });
}
