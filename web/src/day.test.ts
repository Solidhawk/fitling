import { expect, test } from "vitest";
import { addDays, isIsoDay } from "./day";

// A desktop date field accepts a year of five or six digits; FitlingCore's Day reads exactly four.
test("only a date as FitlingCore reads it is taken from the date field", () => {
  expect(isIsoDay("1996-01-10")).toBe(true);
  expect(isIsoDay("19900-05-12")).toBe(false);
  expect(isIsoDay("")).toBe(false);
});

test("a day before and after, across a month and a leap day", () => {
  expect(addDays("2026-11-30", 1)).toBe("2026-12-01");
  expect(addDays("2028-03-01", -1)).toBe("2028-02-29");
});
