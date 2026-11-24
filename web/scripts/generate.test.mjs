import { mkdtemp, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vitest";
import { generate } from "./generate.mjs";

const unit = (value) => ({ stringUnit: { state: "translated", value } });
const color = (red, green, blue, dark) => ({
  colors: [
    { color: { "color-space": "srgb", components: { alpha: "1.000", red, green, blue } }, idiom: "universal" },
    ...(dark
      ? [{ appearances: [{ appearance: "luminosity", value: "dark" }], color: { "color-space": "srgb", components: { alpha: "1.000", ...dark } }, idiom: "universal" }]
      : []),
  ],
});

/** A small copy of Fitling/Resources: two strings, three colours and one image of each kind. */
async function fixture(strings) {
  const root = await mkdtemp(join(tmpdir(), "fitling-resources-"));
  const write = async (path, content) => {
    await mkdir(join(root, path, ".."), { recursive: true });
    await writeFile(join(root, path), typeof content === "string" ? content : JSON.stringify(content));
  };
  await write("Localizable.xcstrings", { sourceLanguage: "nl", strings, version: "1.0" });
  await write("Assets.xcassets/Ground.colorset/Contents.json", color("0xEF", "0xE9", "0xF8", { red: "0x1B", green: "0x15", blue: "0x24" }));
  await write("Assets.xcassets/Ink.colorset/Contents.json", color("0.137", "0.110", "0.200"));
  await write("Assets.xcassets/PartnerRibbon/owl.colorset/Contents.json", color("0x8A", "0xA6", "0xD6"));
  await write("Partners.xcassets/owl/partner-owl-1-body.imageset/partner-owl-1-body.png", "png");
  await write("ExerciseAnimations/abc.webp", "webp");
  await write("ExerciseAnimations/ExerciseAnimations.json", { fps: 12, frames: 24, columns: 6, animations: {} });
  await write("Assets.xcassets/Recipes/0f25.imageset/photo.jpg", "jpg");
  await write("PartnerAnchors.json", { "owl/1": {} });
  const out = await mkdtemp(join(tmpdir(), "fitling-web-"));
  return { resources: root, out };
}

const both = { "tab.today": { localizations: { nl: unit("Vandaag"), en: unit("Today"), de: unit("Heute") } } };

test("keepsPlainStrings", async () => {
  const dirs = await fixture(both);
  await generate(dirs);
  const strings = JSON.parse(await readFile(join(dirs.out, "src/generated/strings.json"), "utf8"));
  expect(strings.nl["tab.today"]).toBe("Vandaag");
  expect(strings.de["tab.today"]).toBe("Heute");
});

test("keepsPlurals", async () => {
  const plural = (one, other) => ({ variations: { plural: { one: unit(one), other: unit(other) } } });
  const dirs = await fixture({
    ...both,
    "n %lld": { localizations: { nl: plural("%lld training", "%lld trainingen"), en: plural("%lld workout", "%lld workouts"), de: plural("%lld Training", "%lld Trainings") } },
  });
  await generate(dirs);
  const strings = JSON.parse(await readFile(join(dirs.out, "src/generated/strings.json"), "utf8"));
  expect(strings.nl["n %lld"]).toEqual({ one: "%lld training", other: "%lld trainingen" });
});

test("failsOnMissingTranslation", async () => {
  const dirs = await fixture({ ...both, "only.dutch": { localizations: { nl: unit("Alleen Nederlands") } } });
  await expect(generate(dirs)).rejects.toThrow("only.dutch");
});

test("convertsColors", async () => {
  const dirs = await fixture(both);
  await generate(dirs);
  const css = await readFile(join(dirs.out, "src/generated/colors.css"), "utf8");
  const [light, dark] = css.split("@media (prefers-color-scheme: dark)");
  expect(light).toContain("--ground: #efe9f8;");
  expect(light).toContain("--ink: #231c33;");
  expect(light).toContain("--partner-ribbon-owl: #8aa6d6;");
  expect(dark).toContain("--ground: #1b1524;");
  // Without a dark variant the light colour holds in dark mode too.
  expect(dark).toContain("--ink: #231c33;");
});

test("copiesImages", async () => {
  const dirs = await fixture(both);
  await generate(dirs);
  expect(await readdir(join(dirs.out, "public/partners"))).toEqual(["partner-owl-1-body.png"]);
  expect((await readdir(join(dirs.out, "public/exercises"))).sort()).toEqual(["ExerciseAnimations.json", "abc.webp"]);
  expect(await readdir(join(dirs.out, "public/recipes"))).toEqual(["0f25.jpg"]);
  expect(JSON.parse(await readFile(join(dirs.out, "src/generated/partnerAnchors.json"), "utf8"))).toEqual({ "owl/1": {} });
});

test("copiesEveryLayerOnTheRealResources", async () => {
  const out = await mkdtemp(join(tmpdir(), "fitling-web-real-"));
  const resources = fileURLToPath(new URL("../../Fitling/Resources", import.meta.url));
  await generate({ resources, out });
  expect((await readdir(join(out, "public/partners"))).length).toBe(1344);
  expect((await readdir(join(out, "public/exercises"))).length).toBe(114);
  const recipes = (await readdir(join(resources, "Assets.xcassets/Recipes"))).filter((name) => name.endsWith(".imageset"));
  expect((await readdir(join(out, "public/recipes"))).length).toBe(recipes.length);
}, 60_000);
