import { expect, test } from "vitest";
import { isIsoDay } from "./day";

// A desktop date field accepts a year of five or six digits; FitlingCore's Day reads exactly four.
test("only a date as FitlingCore reads it is taken from the date field", () => {
  expect(isIsoDay("1996-01-10")).toBe(true);
  expect(isIsoDay("19900-05-12")).toBe(false);
  expect(isIsoDay("")).toBe(false);
});
