// The service worker of the web app (phase 7): which files make up a build, the version of the rules, and the worker
// itself, made from web/sw.js at build time. Run by vite.config.ts; tested in serviceWorker.test.mjs.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

/** What the home-screen app needs to open without a connection, besides the bundle Vite wrote. */
const publicShell = [
  "manifest.webmanifest",
  "icons/apple-touch-icon.png",
  "icons/favicon-32.png",
  "icons/icon-192.png",
  "icons/icon-512.png",
  "icons/icon-maskable-512.png",
];

/** The version of the rules: the first 12 hex digits of their SHA-256; "dev" while there are none. */
export function coreVersion(bytes) {
  return bytes ? createHash("sha256").update(bytes).digest("hex").slice(0, 12) : "dev";
}

/** The files of one build, relative to the app's scope: the page, the bundle (no source maps), the icons, the rules. */
export function shellFiles(bundleFiles, version) {
  const bundle = bundleFiles.filter((file) => !file.endsWith(".map"));
  return ["./", ...bundle, ...publicShell, `fitling-core.wasm.gz?v=${version}`];
}

/** The worker for one build: its file list and a build id made from that list. */
export function workerSource(template, files) {
  if (!template.includes('"__BUILD__"') || !template.includes("[/*__SHELL__*/]")) {
    throw new Error("web/sw.js lacks its placeholders");
  }
  const build = createHash("sha256").update(files.join("\n")).digest("hex").slice(0, 12);
  return template.replace('"__BUILD__"', JSON.stringify(build)).replace("[/*__SHELL__*/]", JSON.stringify(files));
}

/** The rules in public/, as the web job puts them there before the build; undefined when they are not there yet. */
export function readCore(path) {
  try {
    return readFileSync(path);
  } catch {
    return undefined;
  }
}

/** Writes sw.js into the build, next to index.html. Not in the dev server: there every change must show at once. */
export function serviceWorker({ template, version }) {
  return {
    name: "fitling-service-worker",
    apply: "build",
    generateBundle(_options, bundle) {
      const files = shellFiles(Object.keys(bundle).filter((file) => file !== "index.html"), version);
      this.emitFile({ type: "asset", fileName: "sw.js", source: workerSource(readFileSync(template, "utf8"), files) });
    },
  };
}
