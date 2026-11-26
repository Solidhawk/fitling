import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";
import { coreVersion, readCore, serviceWorker } from "./scripts/serviceWorker.mjs";

// The version of the rules the web job put in public/: part of their address and of the service worker, so a kept
// copy never meets newer code (phase 7). "dev" while they are not there.
const core = coreVersion(readCore(new URL("./public/fitling-core.wasm.gz", import.meta.url)));

// Published at https://solidhawk.github.io/fitling/ (D-24).
export default defineConfig({
  base: "/fitling/",
  plugins: [react(), serviceWorker({ template: new URL("./sw.js", import.meta.url), version: core })],
  define: { __CORE_VERSION__: JSON.stringify(core) },
  test: {
    include: ["src/**/*.test.ts", "scripts/**/*.test.mjs"],
  },
});
