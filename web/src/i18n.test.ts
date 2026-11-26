import { expect, test } from "vitest";
import { language, translate } from "./i18n";

test("a plain text in each language", () => {
  expect(translate("nl", "tab.today")).toBe("Vandaag");
  expect(translate("en", "tab.today")).toBe("Today");
  expect(translate("de", "tab.today")).toBe("Heute");
});

test("plurals follow the number", () => {
  expect(translate("nl", "training.program.composed %lld", 2)).toBe("Door de app samengesteld · 2 trainingen");
  expect(translate("nl", "training.program.composed %lld", 1)).toBe("Door de app samengesteld · 1 training");
});

test("arguments fill the placeholders, numbers in the language's own way", () => {
  expect(translate("nl", "menu.unit.piece %@", "4")).toBe("4 stuks");
  expect(translate("nl", "training.program.composed %lld", 2760)).toBe("Door de app samengesteld · 2.760 trainingen");
  expect(translate("en", "training.program.composed %lld", 2760)).toBe("Composed by the app · 2,760 workouts");
});

test("an unknown key is shown as it is, as on iOS", () => {
  expect(translate("nl", "no.such.key")).toBe("no.such.key");
});

test("fallsBackToDutch", () => {
  expect(language(["fr-FR"])).toBe("nl");
  expect(language(["de-AT", "en"])).toBe("de");
  expect(language(["en-GB"])).toBe("en");
  expect(language([])).toBe("nl");
});
