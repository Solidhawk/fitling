import { expect, test } from "vitest";
import { cleanedName, limitedName, nameLimit } from "./name";

// PartnerTests.nameIsTrimmedAndLimited on iOS.
test("nameIsTrimmedAndLimited", () => {
  expect(cleanedName("   Pip de Grote Ontdekkingsreiziger   ")).toBe("Pip de Grote Ontdekkings");

  // Postgres counts code points: a family emoji is seven of them, so three fit in 24.
  const family = "👨‍👩‍👧‍👦";
  expect(cleanedName(family.repeat(4))).toBe(family.repeat(3));
  expect([...cleanedName(family.repeat(4))].length).toBeLessThanOrEqual(nameLimit);

  expect(cleanedName("      ")).toBe("");
  expect(cleanedName("  Pippa ")).toBe("Pippa");
});

test("while typing, spaces stay and a character is never cut in half", () => {
  expect(limitedName("Mr Pip ")).toBe("Mr Pip ");
  expect(limitedName("a".repeat(25))).toBe("a".repeat(24));
  // 20 letters and a family of seven code points do not fit; the family goes as a whole.
  expect(limitedName(`${"b".repeat(20)}👨‍👩‍👧‍👦`)).toBe("b".repeat(20));
});
