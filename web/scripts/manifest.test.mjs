import { readFile } from "node:fs/promises";
import { expect, test } from "vitest";

// The app on the home screen (web phase 7): its manifest, its icons and the tags in index.html.
const web = new URL("../", import.meta.url);

/** Width and height from a PNG's IHDR chunk; throws for anything that is no PNG. */
async function pngSize(path) {
  const bytes = await readFile(new URL(path, web));
  expect([...bytes.subarray(0, 8)]).toEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
}

test("theManifestPointsAtTheIcons", async () => {
  const manifest = JSON.parse(await readFile(new URL("public/manifest.webmanifest", web), "utf8"));
  // Relative to the manifest, so the app opens and stays under /fitling/ on GitHub Pages, as under / locally.
  expect(manifest).toMatchObject({ name: "Fitling", short_name: "Fitling", start_url: "./", scope: "./", id: "./", display: "standalone" });
  // The Ground colorset in light: the splash screen and the bar while the app opens.
  expect(manifest.background_color).toBe("#efe9f8");
  expect(manifest.theme_color).toBe("#efe9f8");
  const purposes = manifest.icons.map((icon) => [icon.src, icon.sizes, icon.purpose ?? "any"]);
  expect(purposes).toEqual([
    ["icons/icon-192.png", "192x192", "any"],
    ["icons/icon-512.png", "512x512", "any"],
    ["icons/icon-maskable-512.png", "512x512", "maskable"],
  ]);
  for (const icon of manifest.icons) {
    const [width, height] = icon.sizes.split("x").map(Number);
    expect(await pngSize(`public/${icon.src}`)).toEqual({ width, height });
  }
  expect(await pngSize("public/icons/apple-touch-icon.png")).toEqual({ width: 180, height: 180 });
  expect(await pngSize("public/icons/favicon-32.png")).toEqual({ width: 32, height: 32 });
});

test("indexLinksTheHomeScreenParts", async () => {
  const html = await readFile(new URL("index.html", web), "utf8");
  expect(html).toContain('<link rel="manifest" href="%BASE_URL%manifest.webmanifest" />');
  expect(html).toContain('<link rel="apple-touch-icon" href="%BASE_URL%icons/apple-touch-icon.png" />');
  expect(html).toContain('<link rel="icon" type="image/png" sizes="32x32" href="%BASE_URL%icons/favicon-32.png" />');
  // The bar follows the ground: light and dark (the Ground colorset).
  expect(html).toContain('<meta name="theme-color" media="(prefers-color-scheme: light)" content="#efe9f8" />');
  expect(html).toContain('<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#1b1524" />');
  expect(html).toContain('<meta name="apple-mobile-web-app-capable" content="yes" />');
  expect(html).toContain('<meta name="apple-mobile-web-app-title" content="Fitling" />');
});
