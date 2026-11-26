import { beforeEach, expect, test, vi } from "vitest";
import { amountText, dayHeading, entryDetail, issueText, recipeSteps, rememberedMenuOptions, rememberMenuOptions } from "./texts";

// The Dutch forms, whatever language runs the tests.
beforeEach(() => {
  vi.stubGlobal("navigator", { languages: ["nl-NL"] });
  return () => vi.unstubAllGlobals();
});

// ShoppingAmount.text: up to two decimals, and only exactly 1 piece is singular.
test("an ingredient's amount", () => {
  expect(amountText(200, "g")).toBe("200 g");
  expect(amountText(250, "ml")).toBe("250 ml");
  expect(amountText(2, "tbsp")).toBe("2 el");
  expect(amountText(0.333, "tsp")).toBe("0,33 tl");
  expect(amountText(1, "piece")).toBe("1 stuk");
  expect(amountText(1.5, "piece")).toBe("1,5 stuks");
  expect(amountText(0.999, "piece")).toBe("1 stuk");
});

// "1 portie" but "1,5 porties": the servings are text, so the plural is chosen by the amount (MenuTabView.detail).
test("a planned meal's servings and energy", () => {
  expect(entryDetail(1, 512)).toBe("1 portie · 512 kcal");
  expect(entryDetail(0.75, 384)).toBe("0,75 portie · 384 kcal");
  expect(entryDetail(1.75, 1112)).toBe("1,75 porties · 1.112 kcal");
});

test("a day of the menu", () => {
  expect(dayHeading("2026-11-24")).toBe("Dinsdag 24 november");
});

test("what the planner could not solve", () => {
  expect(issueText({ kind: "kcalOutOfRange", day: "2026-11-27", kcal: 2463 })).toBe("vrijdag komt uit op 2.463 kcal, buiten je doel.");
  expect(issueText({ kind: "proteinShort", day: "2026-11-27", missingG: 12 })).toBe("vrijdag mist 12 g eiwit.");
  expect(issueText({ kind: "noRecipes", slot: "snack" })).toBe("Geen recepten voor Tussendoor die bij je voorkeuren passen.");
  expect(issueText({ kind: "overBudget", byCents: 1250 })).toBe("€ 12,50 boven je budget.");
});

// RecipeDetailView.steps: the browser's languages, then English and Dutch, then whatever there is.
test("the steps in the user's language", () => {
  expect(recipeSteps({ en: ["Boil."], nl: ["Kook."] }, ["de-DE", "nl-NL"])).toEqual(["Kook."]);
  expect(recipeSteps({ en: ["Boil."], nl: ["Kook."] }, ["fr-FR"])).toEqual(["Boil."]);
  expect(recipeSteps({ fr: ["Bouillir."] }, ["de-DE"])).toEqual(["Bouillir."]);
  expect(recipeSteps({}, ["nl"])).toEqual([]);
});

// MenuViewModel.options: the generator opens with the choices of the last menu, kept on this device.
test("the choices of the last menu", () => {
  const stored = new Map<string, string>();
  vi.stubGlobal("localStorage", { getItem: (key: string) => stored.get(key) ?? null, setItem: (key: string, value: string) => stored.set(key, value) });
  expect(rememberedMenuOptions()).toEqual({ days: 7 });
  rememberMenuOptions({ days: 3, goal: "lose" });
  expect(rememberedMenuOptions()).toEqual({ days: 3, goal: "lose" });
  stored.set("fitling.menuOptions", JSON.stringify({ days: 12, goal: "fly" }));
  expect(rememberedMenuOptions()).toEqual({ days: 7 });
});
