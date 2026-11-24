import { test as base } from "@playwright/test";

export { expect, type Page } from "@playwright/test";

/**
 * Every test, with what went wrong inside the page printed next to a failure: an exception in a screen leaves an
 * empty page, and the assertion alone does not say why.
 */
export const test = base.extend<{ pageErrors: void }>({
  pageErrors: [
    async ({ page }, use, info) => {
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(error.stack ?? error.message));
      page.on("console", (message) => {
        if (message.type() === "error") errors.push(message.text());
      });
      await use();
      if (info.status !== info.expectedStatus && errors.length > 0) {
        console.log(`${info.project.name} › ${info.title}: errors in the page\n${errors.join("\n")}`);
      }
    },
    { auto: true },
  ],
});
