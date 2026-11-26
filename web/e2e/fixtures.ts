import { test as base } from "@playwright/test";

export { expect, type Page } from "@playwright/test";

/**
 * Every test, with what went wrong inside the page printed next to a failure: an exception in a screen leaves an
 * empty page, and the assertion alone does not say why. Swift says why the rules stopped (a fatal error) on stderr,
 * which the app passes to console.warn (fitlingCore.ts). A page that no longer answers, stuck in a loop, leaves no
 * error and no snapshot, so that is said too, and so is every request that failed.
 */
export const test = base.extend<{ pageErrors: void }>({
  pageErrors: [
    async ({ page }, use, info) => {
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(error.stack ?? error.message));
      page.on("console", (message) => {
        if (message.type() === "error" || message.type() === "warning") errors.push(`${message.type()}: ${message.text()}`);
      });
      page.on("crash", () => errors.push("the page crashed"));
      // Which file a "Failed to load resource" was: the console does not say.
      page.on("requestfailed", (request) => errors.push(`request failed: ${request.url()} (${request.failure()?.errorText ?? "?"})`));
      await use();
      if (info.status === info.expectedStatus) return;
      const answers = await Promise.race([
        page.evaluate(() => true).catch(() => false),
        new Promise<boolean>((resolve) => setTimeout(() => resolve(false), 2_000)),
      ]);
      if (!answers) errors.push("the page does not answer");
      if (errors.length > 0) console.log(`${info.project.name} › ${info.title}: errors in the page\n${errors.join("\n")}`);
    },
    { auto: true },
  ],
});
