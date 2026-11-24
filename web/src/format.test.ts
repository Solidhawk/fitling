import { beforeEach, expect, test, vi } from "vitest";
import { fixed, grams, kcal, parseNumber } from "./format";

// The numbers follow the browser's language; these are the Dutch forms, whatever language runs the tests.
beforeEach(() => {
  vi.stubGlobal("navigator", { languages: ["nl-NL"] });
  return () => vi.unstubAllGlobals();
});

// As Measurement(.kilocalories).formatted(.measurement(width: .abbreviated)) in Dutch: grouped, no decimals.
test("kcal in the user's language", () => {
  expect(kcal(2760)).toBe("2.760 kcal");
  expect(kcal(1779.6)).toBe("1.780 kcal");
});

test("grams, a fixed decimal and a typed number", () => {
  expect(grams(128)).toBe("128 g");
  expect(fixed(2, 1)).toBe("2,0");
  expect(parseNumber("180,3")).toBe(180.3);
  expect(parseNumber(" ")).toBeUndefined();
});
