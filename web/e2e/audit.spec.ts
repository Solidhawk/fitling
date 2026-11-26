import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "./fixtures";
import { exercise, finishedWorkout, firstProgramme, openTraining, tapRow } from "./training";
import { openMenu, todaysMenu } from "./menu";
import { fakePush } from "./push";
import { openShopping, shopWithOffers } from "./shopping";
import { admin, createUser, foodEntry, localDay, nl, sharedProduct, signIn } from "./users";

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
  // First the picture, so a failing check below can be seen.
  await page.screenshot({ path: `test-results/screens/${project}-audit-${mode}-${name}.png` });
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => `${mode} ${name}: ${violation.id}`)).toEqual([]);
  if (mode === "groot") {
    // Against the phone's width, not window.innerWidth: content that sticks out widens a phone's layout viewport.
    // Text sticking out of its own box counts too; the partner drawings are clipped on purpose.
    const width = page.viewportSize()?.width ?? 0;
    const sticking = await page.evaluate((width) => {
      const found: string[] = [];
      if (document.documentElement.scrollWidth > width + 1) found.push(`page ${document.documentElement.scrollWidth}px`);
      for (const element of document.querySelectorAll<HTMLElement>("body *")) {
        if (element.closest(".partner-canvas")) continue;
        const box = element.getBoundingClientRect();
        if (box.width === 0) continue;
        const visible = getComputedStyle(element).overflowX === "visible";
        const outside = box.right > width + 1 || box.left < -1;
        // A long value scrolls inside its field, as in a TextField on iOS; the field itself must stay on screen.
        const field = element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement;
        const textOut = visible && !field && element.clientWidth > 0 && element.scrollWidth > element.clientWidth + 1;
        if (outside || textOut) found.push(`${element.tagName.toLowerCase()}.${element.className}`);
      }
      return found.slice(0, 6);
    }, width);
    expect(sticking, `${name}: sticks out at 200 %`).toEqual([]);
  }
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

    // Review Focus: long names and brands at 200 % stay on screen in the lists, the portion and the own product.
    test("Vandaag and logging", async ({ page }, info) => {
      const user = await createUser({ profile: true, creature: true });
      const product = await sharedProduct("Volkoren meergranen desembrood met zonnebloempitten en lijnzaad", {
        brand: "Bakkerij van de Hoogstraat en Zonen",
        serving_size: 35,
        protein_100: null,
      });
      await foodEntry(user.id, { consumed_on: localDay(), name: "Griekse yoghurt met honing, walnoten en vers fruit van het seizoen" });
      await signIn(page, user.email);
      await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
      await check(page, mode, "11-vandaag", info.project.name);
      await page.getByTestId("day.add.breakfast").click();
      await check(page, mode, "20-loggen", info.project.name);
      await page.getByTestId("log.search").fill(product.name);
      await page.getByRole("button", { name: new RegExp(product.name) }).click();
      await expect(page.getByTestId("portion.quantity")).toBeVisible();
      await check(page, mode, "21-portie", info.project.name);
      await page.getByRole("button", { name: nl("meal.breakfast") }).click();
      await page.getByTestId("log.search").fill("");
      await page.getByTestId("log.ownProduct").click();
      await check(page, mode, "22-eigen-product", info.project.name);
      await page.getByRole("button", { name: nl("meal.breakfast") }).click();
      await page.getByTestId("log.scan").click();
      await expect(page.locator('[data-screen="scan"]')).toBeVisible();
      await check(page, mode, "23-scannen", info.project.name);
    });

    // Review Focus: a long name at 200 % on the name plate and in the mood line; at level 1 the locked accessories
    // and colours with their level, as on the iPhone's screens 12 and 23.
    test("Partner", async ({ page }, info) => {
      const user = await createUser({ profile: true, creature: true });
      const { error } = await admin.from("creatures").update({ name: "Wollige Wervelwind Pip" }).eq("user_id", user.id);
      if (error) throw error;
      await foodEntry(user.id, { consumed_on: localDay(), kcal: 2700, protein_g: 130 });
      await signIn(page, user.email);
      await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
      await page.getByRole("tab", { name: nl("partner.title") }).click();
      await expect(page.getByTestId("partner.hero")).toBeVisible({ timeout: 15_000 });
      await check(page, mode, "12-partner", info.project.name);
      await page.getByTestId("partner.item.crown").scrollIntoViewIfNeeded();
      await check(page, mode, "23-partner-onder", info.project.name);
      await page.getByRole("button", { name: nl("partner.edit") }).click();
      await expect(page.getByRole("dialog", { name: nl("partner.edit") })).toBeVisible();
      await check(page, mode, "24-partner-aanpassen", info.project.name);
    });

    // Phase 7: the reminders with their times, the partner's long name in the line under them.
    test("Partner reminders", async ({ page }, info) => {
      await fakePush(page);
      const user = await createUser({ profile: true, creature: true });
      const { error } = await admin.from("creatures").update({ name: "Wollige Wervelwind Pip" }).eq("user_id", user.id);
      if (error) throw error;
      await signIn(page, user.email);
      await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
      await page.getByRole("tab", { name: nl("partner.title") }).click();
      await expect(page.getByTestId("partner.hero")).toBeVisible({ timeout: 15_000 });
      await page.getByTestId("partner.reminders.toggle").click();
      await expect(page.getByTestId("partner.reminders.time.1")).toBeVisible();
      await page.getByTestId("partner.reminders.time.1").scrollIntoViewIfNeeded();
      await check(page, mode, "26-partner-herinneringen", info.project.name);
    });

    test("Partner with everything unlocked", async ({ page }, info) => {
      const user = await createUser({ profile: true, creature: true });
      const { error } = await admin.from("creatures").update({ xp: 30_000, equipped_items: ["scarf", "crown"] }).eq("user_id", user.id);
      if (error) throw error;
      await signIn(page, user.email);
      await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
      await page.getByRole("tab", { name: nl("partner.title") }).click();
      await expect(page.getByTestId("partner.hero")).toBeVisible({ timeout: 15_000 });
      await page.getByTestId("partner.item.crown").scrollIntoViewIfNeeded();
      await check(page, mode, "25-partner-alles", info.project.name);
    });

    // Review Focus: every training screen at 200 % and in dark mode, with a long programme name and a coach note.
    test("Training", async ({ page }, info) => {
      const bench = await exercise("Bench press");
      const programme = await firstProgramme();
      await openTraining(page, async (userID) => {
        await finishedWorkout(userID, bench.id, 9, [[60, 12], [60, 12], [60, 12]]);
        await finishedWorkout(userID, bench.id, 2, [[60, 12], [60, 12], [60, 12]]);
      });
      await check(page, mode, "04-training", info.project.name);
      await page.getByTestId(`training.program.${programme.id}`).click();
      await expect(page.getByRole("heading", { name: programme.name })).toBeVisible();
      await check(page, mode, "05-schema", info.project.name);
      await page.getByTestId(`training.start.${programme.days[0].id}`).click();
      await expect(page.getByRole("dialog", { name: programme.days[0].name })).toBeVisible({ timeout: 15_000 });
      await check(page, mode, "05b-training-loggen", info.project.name);
      await page.getByTestId("workout.options").click();
      await page.getByRole("menuitem", { name: nl("training.workout.later") }).click();
      await page.goBack();
      await expect(page.getByTestId("training.resume")).toBeVisible({ timeout: 15_000 });
      await tapRow(page, nl("training.progress.exercises"));
      await page.getByTestId(`progress.exercise.${bench.id}`).click();
      await expect(page.getByRole("heading", { name: bench.name })).toBeVisible();
      await check(page, mode, "07-per-oefening", info.project.name);
      await page.goBack();
      await page.goBack();
      await page.getByRole("button", { name: nl("training.progress.volume") }).click();
      await check(page, mode, "08-volume", info.project.name);
      await page.goBack();
      await page.getByRole("button", { name: nl("body.title") }).click();
      await check(page, mode, "09-lichaam", info.project.name);
      await page.goBack();
      await page.getByRole("button", { name: nl("photos.title") }).click();
      await check(page, mode, "10-voortgangsfotos", info.project.name);
    });

    test("Composing and a new programme", async ({ page }, info) => {
      await openTraining(page);
      await page.getByTestId("training.compose").click();
      await expect(page.getByTestId("training.compose.start")).toBeVisible();
      await check(page, mode, "06-training-samenstellen", info.project.name);
      await page.getByRole("button", { name: nl("common.cancel") }).click();
      await page.getByTestId("training.program.new").click();
      await page.getByTestId("training.program.name").fill("Mijn eigen schema voor maandag en donderdag");
      await check(page, mode, "11-eigen-schema", info.project.name);
    });

    test("Menu", async ({ page }, info) => {
      await openMenu(page);
      await check(page, mode, "26-menu-leeg", info.project.name);
      await page.getByTestId("menu.generate.first").click();
      await expect(page.getByTestId("menu.generator.make")).toBeVisible();
      await check(page, mode, "27-menu-maken", info.project.name);
      await page.getByTestId("menu.generator.make").click();
      await expect(page.getByTestId(`menu.day.renew.${localDay()}`)).toBeVisible({ timeout: 15_000 });
      await check(page, mode, "28-weekmenu", info.project.name);
      await page.getByTestId("menu.preferences").click();
      await check(page, mode, "29-menu-voorkeuren", info.project.name);
      await page.getByRole("button", { name: nl("common.ok"), exact: true }).click();
      await page.getByTestId("menu.recipes").click();
      await expect(page.getByTestId("menu.recipe.new")).toBeVisible();
      await check(page, mode, "30-recepten", info.project.name);
      await page.getByTestId("menu.recipe.new").click();
      await page.getByTestId("menu.own.title").fill("Ovenschotel met zoete aardappel en spinazie");
      await check(page, mode, "31-eigen-recept", info.project.name);
    });

    test("A recipe and a meal's menu", async ({ page }, info) => {
      let planned: Awaited<ReturnType<typeof todaysMenu>> = [];
      await openMenu(page, async (userID) => {
        planned = await todaysMenu(userID);
      });
      await page.getByTestId(`menu.entry.${planned[1].id}`).click({ button: "right" });
      await expect(page.getByRole("alertdialog")).toBeVisible();
      await check(page, mode, "32-menu-acties", info.project.name);
      await page.getByRole("alertdialog").getByRole("button", { name: nl("menu.swap") }).click();
      await expect(page.getByTestId("menu.picker.search")).toBeVisible();
      await check(page, mode, "33-ander-recept", info.project.name);
      await page.getByRole("button", { name: nl("common.cancel") }).click();
      await page.getByTestId(`menu.entry.${planned[0].id}`).click();
      await expect(page.getByRole("heading", { name: nl("menu.recipe.steps") })).toBeVisible({ timeout: 15_000 });
      await check(page, mode, "34-recept", info.project.name);
    });

    test("Shopping list", async ({ page }, info) => {
      const shop = await shopWithOffers("Proefmarkt", [
        { title: "Halfvolle melk 1 l", cents: 99 },
        { title: "Tomatenblokjes 400 g", cents: 69 },
      ]);
      await openShopping(page);
      await check(page, mode, "35-boodschappen-leeg", info.project.name);
      for (const name of ["Halfvolle melk", "Tomaat", "Volkoren brood van de bakker op de hoek"]) {
        await page.getByTestId("shopping.add.field").fill(name);
        await page.keyboard.press("Enter");
        await expect(page.getByTestId(`shopping.item.${name}`)).toBeVisible({ timeout: 15_000 });
      }
      await page.getByTestId("shopping.shops").click();
      await check(page, mode, "36-supermarkten", info.project.name);
      await page.getByTestId(`shopping.shop.${shop}`).check();
      await page.getByRole("button", { name: nl("common.ok"), exact: true }).click();
      await expect(page.getByTestId("shopping.offer.Halfvolle melk")).toBeVisible({ timeout: 15_000 });
      await expect(page.getByTestId("shopping.question")).toBeVisible();
      await check(page, mode, "37a-aanbiedingen", info.project.name);
      await page.getByTestId("shopping.item.Tomaat").click();
      await expect(page.getByTestId("shopping.item.Tomaat")).toHaveAttribute("aria-pressed", "true", { timeout: 15_000 });
      await check(page, mode, "37-boodschappen", info.project.name);
      await page.getByTestId("shopping.join").click();
      await check(page, mode, "38-meedoen", info.project.name);
      await page.getByRole("button", { name: nl("common.cancel") }).click();
      await page.getByTestId("shopping.invite").click();
      await expect(page.getByRole("alertdialog")).toContainText(/[0-9A-F]{12}/, { timeout: 15_000 });
      await check(page, mode, "39-uitnodiging", info.project.name);
    });

    test("Dagdoel and account", async ({ page }, info) => {
      const user = await createUser({ profile: true, creature: true });
      await signIn(page, user.email);
      await page.getByRole("tab", { name: nl("profile.title") }).click();
      await expect(page.getByTestId("profile.target")).toBeVisible({ timeout: 15_000 });
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

// The longest words are German, the shortest English: every tab at 200 % text in both, with nothing that only a
// sideways scroll reaches, and the reminders under the partner (phase 7).
for (const locale of ["de-DE", "en-US"] as const) {
  test.describe(locale, () => {
    test.use({ locale });
    test.beforeEach(({ page }) => prepare(page, "groot"));

    test("every tab", async ({ page }, info) => {
      await fakePush(page);
      const user = await createUser({ profile: true, creature: true });
      await signIn(page, user.email);
      await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
      await check(page, "groot", `taal-${locale}-vandaag`, info.project.name);
      for (const tab of ["training", "menu", "partner", "target"]) {
        await page.locator(`#tab-${tab}`).click();
        await expect(page.locator(`#panel-${tab} .spinner`)).toHaveCount(0, { timeout: 15_000 });
        await check(page, "groot", `taal-${locale}-${tab}`, info.project.name);
      }
      await page.locator("#tab-partner").click();
      await page.getByTestId("partner.reminders.toggle").click();
      await page.getByTestId("partner.reminders.time.1").scrollIntoViewIfNeeded();
      await check(page, "groot", `taal-${locale}-herinneringen`, info.project.name);
    });
  });
}
