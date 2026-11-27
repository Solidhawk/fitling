import { expect, test } from "vitest";
import { kilogramsPerPound, usesMetric } from "./units";

test("metric everywhere except where iOS uses feet, inches and pounds", () => {
  expect(usesMetric(["nl-NL"])).toBe(true);
  expect(usesMetric(["de-DE"])).toBe(true);
  expect(usesMetric(["nl"])).toBe(true);
  expect(usesMetric(["en-US"])).toBe(false);
  expect(usesMetric(["en-GB"])).toBe(false);
  // Without a region the language's most likely one: English means the United States.
  expect(usesMetric(["en"])).toBe(false);
});

// One pound in kilograms, by definition; every conversion on the web uses this one number (UNFORGET S42).
test("a pound is 0.45359237 kg", () => {
  expect(kilogramsPerPound).toBe(0.45359237);
});
