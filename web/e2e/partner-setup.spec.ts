import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";
import { admin, createUser, nl, signIn } from "./users";

/** Signed in with a profile and no partner yet: the app opens on choosing one. */
async function start(page: Page) {
  const user = await createUser({ profile: true });
  await signIn(page, user.email);
  await expect(page.locator('[data-screen="partnerSetup"]')).toBeAttached();
  return user;
}

function species(page: Page, name: string) {
  return page.getByTestId(`partner.setup.species.${name}`);
}

async function shot(page: Page, name: string, project: string) {
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => `${name}: ${violation.id}`)).toEqual([]);
  await page.screenshot({ path: `test-results/screens/${project}-partner-${name}.png`, fullPage: true });
}

// The steps of OnboardingFlowTests.choosePartner: the owl, "tje" after its name, Klaar.
test("the owl becomes Uiltje and the tabs open", async ({ page }, info) => {
  const user = await start(page);
  await expect(page.getByTestId("partner.setup.done")).toBeDisabled();
  await shot(page, "9-kiezen", info.project.name);
  await species(page, "owl").click();
  await expect(species(page, "owl")).toHaveAttribute("aria-pressed", "true");
  const name = page.getByTestId("partner.setup.name");
  await expect(name).toHaveValue(nl("creature.owl.name"));
  await name.press("End");
  await name.pressSequentially("tje");
  await expect(name).toHaveValue("Uiltje");
  await shot(page, "10-naam", info.project.name);
  await page.getByTestId("partner.setup.done").click();
  await expect(page.locator('[data-screen="home"]')).toBeAttached();
  const { data } = await admin.from("creatures").select("species, name").eq("user_id", user.id).single();
  expect(data).toEqual({ species: "owl", name: "Uiltje" });
});

// PartnerTests.setupStoresTheChoices.
test("setupStoresTheChoices", async ({ page }) => {
  const user = await start(page);
  await species(page, "mole").click();
  await page.getByTestId("partner.setup.name").fill("Vonk");
  await page.getByRole("radio", { name: nl("partner.color %lld").replace("%lld", "3") }).click();
  await page.getByRole("radio", { name: new RegExp(nl("partner.tone.funny")) }).click();
  await page.getByTestId("partner.setup.done").click();
  await expect(page.locator('[data-screen="home"]')).toBeAttached();
  const { data } = await admin
    .from("creatures")
    .select("species, name, color_index, tone, created_on, body_shape, xp")
    .eq("user_id", user.id)
    .single();
  expect(data).toEqual({
    species: "mole",
    name: "Vonk",
    color_index: 2,
    tone: "funny",
    created_on: new Date().toISOString().slice(0, 10),
    body_shape: 0.3,
    xp: 0,
  });
});

// PartnerTests.nameIsTrimmedAndLimited, in the field itself: the 25th letter does not appear.
test("nameStopsAt24Characters", async ({ page }) => {
  await start(page);
  await species(page, "owl").click();
  const name = page.getByTestId("partner.setup.name");
  await name.fill("");
  await name.pressSequentially("a".repeat(25));
  await expect(name).toHaveValue("a".repeat(24));
  await name.fill("   ");
  await expect(page.getByTestId("partner.setup.done")).toBeDisabled();
});

// PartnerTests.choosingAnotherSpeciesOnlyReplacesTheSuggestedName.
test("choosingAnotherSpeciesOnlyReplacesTheSuggestedName", async ({ page }) => {
  await start(page);
  const name = page.getByTestId("partner.setup.name");
  await species(page, "bumblebee").click();
  await expect(name).toHaveValue(nl("creature.bumblebee.name"));
  await species(page, "frog").click();
  await expect(name).toHaveValue(nl("creature.frog.name"));
  await name.fill("Keitje");
  await species(page, "owl").click();
  await expect(name).toHaveValue("Keitje");
});

// PartnerTests.aPartnerFromAnotherDeviceIsKept: the owl made elsewhere stays, the bumblebee is not stored.
test("aPartnerFromAnotherDeviceIsKept", async ({ page }) => {
  const user = await start(page);
  const elsewhere = await admin.from("creatures").insert({
    user_id: user.id,
    species: "owl",
    name: "Uiltje",
    color_index: 0,
    tone: "sweet",
    created_on: new Date().toISOString().slice(0, 10),
    body_shape: 0.3,
    updated_at: new Date().toISOString(),
  });
  expect(elsewhere.error).toBeNull();
  await species(page, "bumblebee").click();
  await page.getByTestId("partner.setup.done").click();
  await expect(page.locator('[data-screen="home"]')).toBeAttached();
  const { data } = await admin.from("creatures").select("species, name").eq("user_id", user.id);
  expect(data).toEqual([{ species: "owl", name: "Uiltje" }]);
});

test("saveFailureShowsServerError", async ({ page }) => {
  const user = await start(page);
  await species(page, "owl").click();
  await page.route("**/rest/v1/creatures*", (route) => route.abort());
  await page.getByTestId("partner.setup.done").click();
  await expect(page.getByRole("alertdialog", { name: nl("error.server") })).toBeVisible();
  const { data } = await admin.from("creatures").select("user_id").eq("user_id", user.id).maybeSingle();
  expect(data).toBeNull();
});

test.describe("at 200 % text", () => {
  // Two species in a row at very large text, as at the accessibility sizes on iOS.
  test("twoColumnsAtLargeText", async ({ page }, info) => {
    await start(page);
    await page.addStyleTag({ content: "html { font-size: 200%; }" });
    const [first, second, third] = await Promise.all(["bumblebee", "mole", "frog"].map((name) => species(page, name).boundingBox()));
    expect(second?.y).toBe(first?.y);
    expect(third!.y).toBeGreaterThan(first!.y);
    await shot(page, "9-kiezen-groot", info.project.name);
  });
});
