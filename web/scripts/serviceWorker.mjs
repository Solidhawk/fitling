// The service worker of the web app (phase 7): which files make up a build, the version of the rules, and the worker
// itself, made from web/sw.js at build time. Run by vite.config.ts; tested in serviceWorker.test.mjs.
import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

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

/**
 * The worker for one build: its file list, a build id made from that list and from `contents` (the files whose name
 * stays the same from build to build: the page, the manifest, the icons), and the version of the media.
 */
export function workerSource(template, files, { contents, media }) {
  if (!template.includes('"__BUILD__"') || !template.includes("[/*__SHELL__*/]") || !template.includes('"__MEDIA__"')) {
    throw new Error("web/sw.js lacks its placeholders");
  }
  const hash = createHash("sha256").update(files.join("\n"));
  for (const content of contents) hash.update(createHash("sha256").update(content).digest());
  const build = hash.digest("hex").slice(0, 12);
  return template
    .replace('"__BUILD__"', JSON.stringify(build))
    .replace("[/*__SHELL__*/]", JSON.stringify(files))
    .replace('"__MEDIA__"', JSON.stringify(media));
}

/** The media folders of public/: partners, exercise sheets and recipe photos, under unversioned addresses. */
const mediaFolders = ["partners", "exercises", "recipes"];

/** Every media file under `publicDir` as [address, content], in a fixed order. */
export function mediaFiles(publicDir) {
  const found = [];
  const walk = (folder) => {
    for (const name of readdirSync(folder).sort()) {
      const path = join(folder, name);
      if (statSync(path).isDirectory()) walk(path);
      else found.push([relative(publicDir, path).split("\\").join("/"), readFileSync(path)]);
    }
  };
  for (const folder of mediaFolders) if (existsSync(join(publicDir, folder))) walk(join(publicDir, folder));
  return found;
}

/** The version of the media: the first 12 hex digits of a SHA-256 over their addresses and contents. */
export function mediaVersion(files) {
  const hash = createHash("sha256");
  for (const [address, content] of files) hash.update(address).update("\0").update(createHash("sha256").update(content).digest());
  return hash.digest("hex").slice(0, 12);
}

/** The rules in public/, as the web job puts them there before the build; undefined when they are not there yet. */
export function readCore(path) {
  try {
    return readFileSync(path);
  } catch {
    return undefined;
  }
}

/**
 * Writes sw.js into the build, next to index.html. Not in the dev server: there every change must show at once. After
 * Vite's own plugins, so the page it made is in the bundle.
 */
export function serviceWorker({ template, version }) {
  let publicDir;
  return {
    name: "fitling-service-worker",
    apply: "build",
    enforce: "post",
    configResolved(config) {
      publicDir = config.publicDir;
    },
    generateBundle(_options, bundle) {
      const files = shellFiles(Object.keys(bundle).filter((file) => file !== "index.html"), version);
      const page = bundle["index.html"];
      if (page?.type !== "asset") throw new Error("the build has no index.html");
      const contents = [page.source, ...publicShell.map((file) => readFileSync(join(publicDir, file)))];
      const media = mediaVersion(mediaFiles(publicDir));
      this.emitFile({ type: "asset", fileName: "sw.js", source: workerSource(readFileSync(template, "utf8"), files, { contents, media }) });
    },
  };
}
