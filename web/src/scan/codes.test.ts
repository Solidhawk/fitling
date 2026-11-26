import { expect, test } from "vitest";
import { NewCodes } from "./codes";

// ScanSheet on iOS keeps the last code: the camera reports a barcode many times a second while it is in view.
test("eachCodeIsPassedOnOnceWhileInView", () => {
  const codes = new NewCodes();
  expect(codes.accept("4006381333931")).toBe(true);
  expect(codes.accept("4006381333931")).toBe(false);
  expect(codes.accept("8712100849084")).toBe(true);
  expect(codes.accept("4006381333931")).toBe(true);
});
