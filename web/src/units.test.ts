import { expect, test } from "vitest";
import { usesMetric } from "./units";

test("metric everywhere except where iOS uses feet, inches and pounds", () => {
  expect(usesMetric(["nl-NL"])).toBe(true);
  expect(usesMetric(["de-DE"])).toBe(true);
  expect(usesMetric(["nl"])).toBe(true);
  expect(usesMetric(["en-US"])).toBe(false);
  expect(usesMetric(["en-GB"])).toBe(false);
  // Without a region the language's most likely one: English means the United States.
  expect(usesMetric(["en"])).toBe(false);
});
