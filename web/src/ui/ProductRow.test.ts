import { expect, test } from "vitest";
import { initial } from "./ProductRow";

// ProductThumbnailTests on iOS.
test("thePlaceholderShowsTheFirstLetterOrDigit", () => {
  expect(initial("volkorenbrood")).toBe("V");
  expect(initial("  'Oma's taart")).toBe("O");
  expect(initial("7up")).toBe("7");
  expect(initial("")).toBe("–");
});
