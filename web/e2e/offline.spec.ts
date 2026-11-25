import { expect, type Page, test } from "./fixtures";
import { admin, createUser, nl, sharedProduct, signIn } from "./users";

// The app on the home screen (web phase 7): it opens without a connection, logging waits until the connection is
// back, and every build brings its own rules. Runs in the offline projects, where the service worker is allowed
// (playwright.config.ts).

/** Signed in, with the service worker installed and in charge of the page (the first visit installs it). */
async function installed(page: Page) {
  const user = await createUser({ profile: true, creature: true });
  await signIn(page, user.email);
  await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
  await page.evaluate(() => navigator.serviceWorker.ready.then(() => undefined));
  await page.reload();
  await expect.poll(() => page.evaluate(() => navigator.serviceWorker.controller !== null)).toBe(true);
  await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
  return user;
}

const supabase = `${process.env.VITE_SUPABASE_URL ?? ""}/**`;

/**
 * Without a connection, or back. Chromium cuts the whole network, so the page itself has to come from the service
 * worker. Playwright's WebKit stops such a reload with "WebKit encountered an internal error" (CI run 45695264777), so
 * there only the server is cut off: everything the app does without Supabase is tested the same, the page from the
 * worker in Chromium.
 */
async function setOffline(page: Page, offline: boolean) {
  const context = page.context();
  if (context.browser()?.browserType().name() !== "webkit") return context.setOffline(offline);
  if (offline) await context.route(supabase, (route) => route.abort("internetdisconnected"));
  else await context.unroute(supabase);
}

/** The access token as if it ran out an hour ago: the next start has to refresh it, which needs the server. */
async function expireToken(page: Page) {
  await page.evaluate(() => {
    const session = JSON.parse(localStorage.getItem("fitling-session") ?? "{}") as { expires_at?: number };
    session.expires_at = Math.floor(Date.now() / 1000) - 3600;
    localStorage.setItem("fitling-session", JSON.stringify(session));
  });
}

async function count(table: "food_entries" | "water_entries", userID: string): Promise<number> {
  const { data, error } = await admin.from(table).select("id").eq("user_id", userID);
  if (error) throw error;
  return data.length;
}

test("theManifestAndIconsAreServed", async ({ page }) => {
  await page.goto("./");
  const manifest = (await (await page.request.get("manifest.webmanifest")).json()) as { icons: { src: string }[] };
  for (const icon of manifest.icons) expect((await page.request.get(icon.src)).ok()).toBe(true);
  expect((await page.request.get("icons/apple-touch-icon.png")).ok()).toBe(true);
});

// The next morning in the tram: the token ran out overnight and cannot be refreshed, and Vandaag opens all the same,
// as the iPhone does.
test("theAppOpensWithoutAConnection", async ({ page }) => {
  await installed(page);
  await expireToken(page);
  await setOffline(page, true);
  await page.reload();
  await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
  await expect(page.getByText(nl("common.connection.title"))).toHaveCount(0);
  await setOffline(page, false);
});

// Review Focus: a meal logged without a connection is there exactly once once the connection is back, also when the
// page is reloaded while it is being sent.
test("offlineLogArrivesOnce", async ({ page }) => {
  const user = await installed(page);
  const product = await sharedProduct("Appel");
  // Logged once with a connection, so it is among the recent products this browser keeps.
  await page.getByTestId("day.add.breakfast").click();
  await page.getByTestId("log.search").fill(product.name);
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  await page.getByTestId("portion.save").click();
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/250\s?kcal/);
  await page.getByTestId("day.add.breakfast").click();
  await expect(page.getByRole("button", { name: new RegExp(product.name) })).toBeVisible();
  await page.getByRole("button", { name: nl("common.cancel") }).click();

  await setOffline(page, true);
  await page.reload();
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/250\s?kcal/, { timeout: 15_000 });
  await page.getByTestId("day.add.breakfast").click();
  await page.getByRole("button", { name: new RegExp(product.name) }).click();
  await page.getByTestId("portion.save").click();
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/500\s?kcal/);
  await page.getByTestId("water.add").click();
  await expect(page.getByTestId("water.amount")).toHaveText(/250\s?ml/);
  // Still there after a reload without a connection, and not on the server yet.
  await page.reload();
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/500\s?kcal/, { timeout: 15_000 });
  await expect(page.getByTestId("water.amount")).toHaveText(/250\s?ml/);
  expect(await count("food_entries", user.id)).toBe(1);
  expect(await count("water_entries", user.id)).toBe(0);

  // Back online, and reloaded straight away: what is being sent is sent again, and still arrives once.
  await setOffline(page, false);
  await page.reload();
  await expect(page.getByTestId("day.kcal.breakfast")).toHaveText(/500\s?kcal/, { timeout: 15_000 });
  await expect.poll(() => count("food_entries", user.id)).toBe(2);
  await expect.poll(() => count("water_entries", user.id)).toBe(1);
  await page.reload();
  await expect(page.getByTestId("water.amount")).toHaveText(/250\s?ml/, { timeout: 15_000 });
  expect(await count("food_entries", user.id)).toBe(2);
  expect(await count("water_entries", user.id)).toBe(1);
});

test("theCoreFollowsTheBuild", async ({ page }) => {
  await installed(page);
  const worker = await (await page.request.get("sw.js")).text();
  const version = /fitling-core\.wasm\.gz\?v=([0-9a-f]{12})/.exec(worker)?.[1];
  expect(version).toMatch(/^[0-9a-f]{12}$/);
  // The app asks for the rules of its own build: the version the worker keeps, never an unversioned copy.
  const asked = await page.evaluate(() => performance.getEntriesByType("resource").map((entry) => entry.name).filter((name) => name.includes("fitling-core")));
  expect(asked.length).toBeGreaterThan(0);
  expect(asked.every((name) => name.endsWith(`fitling-core.wasm.gz?v=${version}`))).toBe(true);
});
