import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "./fixtures";
import { admin, createUser, foodEntry, localDay, nl, signIn } from "./users";

// PartnerTests and CreatureHistoryTests on iOS: the partner tab of the web version (phase 3).

function daysBefore(count: number): string {
  const date = new Date();
  date.setDate(date.getDate() - count);
  return localDay(date);
}

/** A user with a profile (2760 kcal) and an owl; `creature` changes its row before signing in. */
async function start(page: Page, creature: Record<string, unknown> = {}) {
  const user = await createUser({ profile: true, creature: true });
  if (Object.keys(creature).length > 0) {
    const { error } = await admin.from("creatures").update(creature).eq("user_id", user.id);
    if (error) throw error;
  }
  return user;
}

async function openPartner(page: Page, email: string) {
  await signIn(page, email);
  await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
  await page.getByRole("tab", { name: nl("partner.title") }).click();
  await expect(page.getByTestId("partner.hero")).toBeVisible({ timeout: 15_000 });
}

/** Logged within the target and over the protein goal, as on a good day. */
async function goodDay(userID: string, day: string) {
  await foodEntry(userID, { consumed_on: day, meal: "dinner", name: "Pasta", kcal: 2700, protein_g: 130 });
}

async function stored(userID: string) {
  const { data, error } = await admin.from("creatures").select("name, tone, color_index, equipped_items, xp").eq("user_id", userID).single();
  if (error) throw error;
  return data;
}

test("todayShowsWhatIsEarnedSoFar", async ({ page }, info) => {
  const user = await start(page);
  await goodDay(user.id, localDay());
  await openPartner(page, user.email);
  await expect(page.getByTestId("partner.today.logging")).toContainText(/\+\s?\d+ XP/);
  await expect(page.getByTestId("partner.today.target")).toContainText(/\+\s?\d+ XP/);
  await expect(page.getByTestId("partner.today.protein")).toContainText(/\+\s?\d+ XP/);
  await expect(page.getByTestId("partner.today.workout")).not.toContainText("XP");
  await expect(page.getByTestId("partner.hero")).toContainText(nl("partner.level %lld").replace("%lld", "1"));
  await page.screenshot({ path: `test-results/screens/${info.project.name}-partner.png`, fullPage: true });
  const axe = await new AxeBuilder({ page }).analyze();
  expect(axe.violations.map((violation) => violation.id)).toEqual([]);
});

test("wearingACapTakesOffTheCrown", async ({ page }) => {
  // Far past level 15, where the crown unlocks.
  const user = await start(page, { xp: 30_000 });
  await openPartner(page, user.email);
  const crown = page.getByRole("switch", { name: nl("partner.item.crown") });
  const cap = page.getByRole("switch", { name: nl("partner.item.cap") });
  await crown.click();
  await expect(crown).toBeChecked();
  await cap.click();
  await expect(cap).toBeChecked();
  await expect(crown).not.toBeChecked();
  await expect.poll(async () => (await stored(user.id)).equipped_items).toEqual(["cap"]);
});

test("lockedItemsShowTheirLevel", async ({ page }, info) => {
  const user = await start(page);
  await openPartner(page, user.email);
  const locked = page.getByTestId("partner.item.crown");
  await expect(locked).toContainText(nl("partner.locked %lld").replace("%lld", "15"));
  await expect(page.getByRole("switch", { name: nl("partner.item.crown") })).toHaveCount(0);
  await expect(page.getByRole("switch")).toHaveCount(0);
  await page.getByTestId("partner.item.crown").scrollIntoViewIfNeeded();
  await page.screenshot({ path: `test-results/screens/${info.project.name}-partner-accessoires.png` });
});

test("lockedColoursCannotBeChosen", async ({ page }) => {
  const user = await start(page);
  await openPartner(page, user.email);
  const locked = page.getByRole("radio", { name: nl("partner.color.locked %lld %lld").replace("%1$lld", "4").replace("%2$lld", "5") });
  await expect(locked).toBeDisabled();
  await page.getByRole("radio", { name: nl("partner.color %lld").replace("%lld", "2") }).click();
  await expect(page.getByRole("radio", { name: nl("partner.color %lld").replace("%lld", "2") })).toBeChecked();
  await expect.poll(async () => (await stored(user.id)).color_index).toBe(1);
});

test("renameAndToneAreSaved", async ({ page }, info) => {
  const user = await start(page);
  await openPartner(page, user.email);
  await page.getByRole("button", { name: nl("partner.edit") }).click();
  const sheet = page.getByRole("dialog", { name: nl("partner.edit") });
  await expect(sheet).toBeVisible();
  await page.screenshot({ path: `test-results/screens/${info.project.name}-partner-aanpassen.png` });
  const name = sheet.getByRole("textbox", { name: nl("partner.setup.name") });
  await name.fill("  ");
  await expect(sheet.getByRole("button", { name: nl("common.save") })).toBeDisabled();
  await name.fill("Pluim");
  await sheet.getByRole("radio", { name: new RegExp(nl("partner.tone.coach")) }).click();
  await sheet.getByRole("button", { name: nl("common.save") }).click();
  await expect(sheet).toBeHidden();
  await expect(page.getByTestId("partner.hero")).toContainText("Pluim");
  await expect.poll(async () => (await stored(user.id)).name).toBe("Pluim");
  expect((await stored(user.id)).tone).toBe("coach");
});

test("finishedDaysBringNewsOnce", async ({ page }, info) => {
  // Four good days since the partner came, at least 30 XP each: past level 2 (100 XP), where the scarf unlocks.
  const user = await start(page, { created_on: daysBefore(5) });
  for (const days of [4, 3, 2, 1]) await goodDay(user.id, daysBefore(days));
  await openPartner(page, user.email);
  const news = page.getByRole("alertdialog", { name: nl("partner.news.title") });
  await expect(news).toBeVisible();
  await expect(news).toContainText(nl("partner.news.level %lld").replace("%lld", "2"));
  await expect(news).toContainText(nl("partner.news.item %@").replace("%@", nl("partner.item.scarf")));
  await page.screenshot({ path: `test-results/screens/${info.project.name}-partner-nieuws.png` });
  await news.getByRole("button", { name: nl("common.ok") }).click();
  await expect(news).toBeHidden();
  await page.reload();
  await page.getByRole("tab", { name: nl("partner.title") }).click();
  await expect(page.getByTestId("partner.hero")).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole("switch", { name: nl("partner.item.scarf") })).toBeVisible();
  await expect(page.getByRole("alertdialog")).toHaveCount(0);
});

test("vandaagShowsTheProcessedPartner", async ({ page }) => {
  // 250 XP is level 2; four good days bring it past 300, level 3, where the second form starts.
  const user = await start(page, { created_on: daysBefore(5), xp: 250 });
  for (const days of [4, 3, 2, 1]) await goodDay(user.id, daysBefore(days));
  await signIn(page, user.email);
  await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
  await expect(page.getByTestId("day.progress").locator('img[src*="partner-owl-2-"]').first()).toBeAttached();
  await expect(page.getByTestId("day.progress").locator('img[src*="partner-owl-1-"]')).toHaveCount(0);
});
