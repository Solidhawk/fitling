import { defineConfig, devices } from "@playwright/test";

// The Safari engine on an iPhone and Chrome on an Android phone, in Dutch, against the built app.
export default defineConfig({
  testDir: "e2e",
  outputDir: "test-results/output",
  use: { baseURL: "http://localhost:4173/fitling/", locale: "nl-NL" },
  projects: [
    { name: "webkit", use: { ...devices["iPhone 15"] } },
    { name: "chromium", use: { ...devices["Pixel 7"] } },
  ],
  webServer: { command: "npx vite preview --port 4173 --strictPort", url: "http://localhost:4173/fitling/", reuseExistingServer: false },
});
