import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "./fixtures";
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
  await page.goto(await confirmationLink(email));
  await expect(page.locator('[data-screen="onboarding"]')).toBeAttached();
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

// A friend opens the link for the first time: creating an account comes first, signing in is the other button
// (UNFORGET A10).
test("the welcome screen offers to create an account first", async ({ page }) => {
  await page.goto("./");
  await expect(page.getByTestId("welcome.signUp")).toHaveText(nl("auth.signUp.title"));
  await expect(page.getByTestId("welcome.email")).toHaveText(nl("auth.signIn.title"));
  await page.getByTestId("welcome.signUp").click();
  await expect(page.getByTestId("auth.submit")).toHaveText(nl("auth.signUp.submit"));
});

/** The answer of Supabase when the address has an account and email confirmation is off, as on fitling-dev. */
async function signUpFindsAnAccount(page: Page) {
  await page.route("**/auth/v1/signup*", (route) =>
    route.fulfill({
      status: 422,
      contentType: "application/json",
      body: JSON.stringify({ code: 422, error_code: "user_already_exists", msg: "User already registered" }),
    }),
  );
}

// Someone who already has an account creates one again: the same password signs them in (UNFORGET A1).
test("creating an account that exists signs in with the same password", async ({ page }) => {
  const user = await createUser({ profile: true, creature: true });
  await signUpFindsAnAccount(page);
  await page.goto("./");
  await page.getByTestId("welcome.signUp").click();
  await page.getByLabel(nl("auth.email.field")).fill(user.email);
  await page.getByLabel(nl("auth.password.field")).fill(password);
  await page.getByTestId("auth.submit").click();
  await expect(page.locator('[data-screen="home"]')).toBeAttached();
});

// With another password the form says there is an account and turns to signing in, the address kept (A1).
test("creating an account that exists with another password turns to signing in", async ({ page }) => {
  const user = await createUser({ profile: true, creature: true });
  await signUpFindsAnAccount(page);
  await page.goto("./");
  await page.getByTestId("welcome.signUp").click();
  await page.getByLabel(nl("auth.email.field")).fill(user.email);
  await page.getByLabel(nl("auth.password.field")).fill("niet-het-wachtwoord");
  await page.getByTestId("auth.submit").click();
  await expect(page.getByText(nl("auth.error.userExists"))).toBeVisible();
  await expect(page.getByTestId("auth.submit")).toHaveText(nl("auth.signIn.submit"));
  await expect(page.getByLabel(nl("auth.email.field"))).toHaveValue(user.email);
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
