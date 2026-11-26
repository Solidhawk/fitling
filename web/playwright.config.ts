import { defineConfig, devices } from "@playwright/test";

// The Safari engine on an iPhone and Chrome on an Android phone, in Dutch, against the built app. The service worker
// is blocked there: it would answer before page.route, which many specs use to stand in for the server. The offline
// projects allow it and run only what is about the app on the home screen (offline.spec.ts).
const offline = /offline\.spec\.ts/;

export default defineConfig({
  testDir: "e2e",
  outputDir: "test-results/output",
  use: { baseURL: "http://localhost:4173/fitling/", locale: "nl-NL" },
  projects: [
    { name: "webkit", testIgnore: offline, use: { ...devices["iPhone 15"], serviceWorkers: "block" } },
    { name: "chromium", testIgnore: offline, use: { ...devices["Pixel 7"], serviceWorkers: "block" } },
    { name: "webkit-offline", testMatch: offline, use: { ...devices["iPhone 15"], serviceWorkers: "allow" } },
    { name: "chromium-offline", testMatch: offline, use: { ...devices["Pixel 7"], serviceWorkers: "allow" } },
  ],
  webServer: { command: "npx vite preview --port 4173 --strictPort", url: "http://localhost:4173/fitling/", reuseExistingServer: false },
});
