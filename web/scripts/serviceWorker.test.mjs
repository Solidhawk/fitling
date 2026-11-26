import { expect, test } from "vitest";
import { coreVersion, shellFiles, workerSource } from "./serviceWorker.mjs";

// The service worker of the app on the home screen (web phase 7): what it keeps, and that every build has its own.

test("theShellHoldsTheBuildAndTheRules", () => {
  const files = shellFiles(["assets/index-1a2b.js", "assets/index-3c4d.css", "assets/index-1a2b.js.map", "assets/scan-5e6f.js"], "0f1e2d3c4b5a");
  expect(files).toEqual([
    "./",
    "assets/index-1a2b.js",
    "assets/index-3c4d.css",
    "assets/scan-5e6f.js",
    "manifest.webmanifest",
    "icons/apple-touch-icon.png",
    "icons/favicon-32.png",
    "icons/icon-192.png",
    "icons/icon-512.png",
    "icons/icon-maskable-512.png",
    // The rules of this build: their version in the address, so an old copy never serves new code.
    "fitling-core.wasm.gz?v=0f1e2d3c4b5a",
  ]);
});

test("theRulesVersionIsTheirContent", () => {
  expect(coreVersion(new TextEncoder().encode("rules one"))).toMatch(/^[0-9a-f]{12}$/);
  expect(coreVersion(new TextEncoder().encode("rules one"))).not.toBe(coreVersion(new TextEncoder().encode("rules two")));
  // Without the rules (a build before the WebAssembly job, the dev server): a fixed word, never an empty version.
  expect(coreVersion(undefined)).toBe("dev");
});

test("everyBuildHasItsOwnWorker", () => {
  const template = 'const build = "__BUILD__";\nconst shell = [/*__SHELL__*/];\n';
  const first = workerSource(template, ["./", "assets/a-1.js"]);
  const second = workerSource(template, ["./", "assets/a-2.js"]);
  expect(first).toContain('const shell = ["./","assets/a-1.js"];');
  expect(first).toMatch(/const build = "[0-9a-f]{12}";/);
  expect(first).not.toBe(second);
  expect(() => workerSource("const nothing = 1;", ["./"])).toThrow();
});
