import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "./fixtures";
import { confirmationLink, createUser, nl, password, signIn } from "./users";

const partners = ["bumblebee", "mole", "frog", "owl", "hedgehog", "snail", "axolotl", "seal", "penguin", "turtle", "rabbit", "raccoon", "ladybird", "octopus", "squirrel", "lamb"];

test("the catalog shows the sixteen partners with their names", async ({ page }) => {
  await page.goto("./");
  const tiles = page.locator('[data-screen="welcome"] [role="img"]');
  await expect(tiles).toHaveCount(16);
  for (const [index, species] of partners.entries()) {
    await expect(tiles.nth(index)).toHaveAttribute("aria-label", nl(`creature.${species}.name`));
  }
});

test("signing up asks for the email link and then starts the onboarding", async ({ page }) => {
  const email = `e2e-${crypto.randomUUID()}@fitling.test`;
  await page.goto("./");
  await page.getByTestId("welcome.email").click();
  await page.getByRole("button", { name: nl("auth.switch.toSignUp") }).click();
  await page.getByLabel(nl("auth.email.field")).fill(email);
  await page.getByLabel(nl("auth.password.field")).fill(password);
  await page.getByTestId("auth.submit").click();
  await expect(page.getByRole("heading", { name: nl("auth.verify.title") })).toBeVisible();
  // "In this browser", not "on this iPhone" (UNFORGET S38).
  await expect(page.getByText(nl("auth.verify.body.web %@").replace("%@", email))).toBeVisible();
  await page.goto(await confirmationLink(email));
  await expect(page.locator('[data-screen="onboarding"]')).toBeAttached();
});

// The web has only email: the reset message does not point at Apple or Google (UNFORGET S38).
test("asking for a reset link names no other way to sign in", async ({ page }) => {
  const user = await createUser({ profile: true, creature: true });
  await page.goto("./");
  await page.getByTestId("welcome.email").click();
  await page.getByRole("button", { name: nl("auth.forgot.link") }).click();
  await page.getByLabel(nl("auth.email.field")).fill(user.email);
  await page.getByRole("button", { name: nl("auth.forgot.submit") }).click();
  await expect(page.getByText(nl("auth.reset.sent.web"))).toBeVisible();
});

test("a wrong password shows the app's message", async ({ page }) => {
  const user = await createUser({ profile: true, creature: true });
  await page.goto("./");
  await page.getByTestId("welcome.email").click();
  await page.getByLabel(nl("auth.email.field")).fill(user.email);
  await page.getByLabel(nl("auth.password.field")).fill("niet-het-wachtwoord");
  await page.getByTestId("auth.submit").click();
  await expect(page.getByText(nl("auth.error.invalidCredentials"))).toBeVisible();
});

test("a user with a profile and a partner lands on the tabs", async ({ page }) => {
  const user = await createUser({ profile: true, creature: true });
  await signIn(page, user.email);
  await expect(page.locator('[data-screen="home"]')).toBeAttached();
});

test("a user with a profile but no partner chooses one first", async ({ page }) => {
  const user = await createUser({ profile: true });
  await signIn(page, user.email);
  await expect(page.locator('[data-screen="partnerSetup"]')).toBeAttached();
});

for (const scheme of ["light", "dark"] as const) {
  test(`welcome ${scheme}: accessible, with screenshots`, async ({ page }, info) => {
    await page.emulateMedia({ colorScheme: scheme });
    await page.goto("./");
    await expect(page.locator('[data-screen="welcome"] [role="img"]')).toHaveCount(16);
    // Every partner picture has loaded, so the screenshot shows them.
    await page.waitForFunction(() => [...document.images].every((image) => image.complete && image.naturalWidth > 0));
    const welcome = await new AxeBuilder({ page }).analyze();
    expect(welcome.violations.map((violation) => violation.id)).toEqual([]);
    await page.screenshot({ path: `test-results/screens/${info.project.name}-welkom-${scheme === "light" ? "licht" : "donker"}.png`, fullPage: true });
    await page.getByTestId("welcome.email").click();
    const form = await new AxeBuilder({ page }).analyze();
    expect(form.violations.map((violation) => violation.id)).toEqual([]);
    await page.screenshot({ path: `test-results/screens/${info.project.name}-inloggen-${scheme === "light" ? "licht" : "donker"}.png` });
  });
}
