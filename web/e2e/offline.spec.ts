import { expect, type Page, test } from "./fixtures";
import { createUser, nl, signIn } from "./users";

// The app on the home screen (web phase 7): it opens without a connection, and every build brings its own rules.
// Runs in the offline projects, where the service worker is allowed (playwright.config.ts).

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

test("theManifestAndIconsAreServed", async ({ page }) => {
  await page.goto("./");
  const manifest = (await (await page.request.get("manifest.webmanifest")).json()) as { icons: { src: string }[] };
  for (const icon of manifest.icons) expect((await page.request.get(icon.src)).ok()).toBe(true);
  expect((await page.request.get("icons/apple-touch-icon.png")).ok()).toBe(true);
});

test("theAppOpensWithoutAConnection", async ({ page, context }) => {
  await installed(page);
  await context.setOffline(true);
  await page.reload();
  // The page and the rules come from the device; what only the server knows cannot come, and the app says so.
  await expect(page.getByText(nl("common.connection.title"))).toBeVisible({ timeout: 15_000 });
  await context.setOffline(false);
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
