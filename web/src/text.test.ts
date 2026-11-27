import { expect, test } from "vitest";
import { limitedText } from "./text";

test("a text is cut by code points between whole characters, as Postgres counts them", () => {
  expect(limitedText("a".repeat(41), 40)).toBe("a".repeat(40));
  // A flag is two code points (four UTF-16 units): one that does not fit stays out whole.
  expect(limitedText(`${"a".repeat(39)}🇳🇱`, 40)).toBe("a".repeat(39));
  expect(limitedText("🇳🇱".repeat(30), 40)).toBe("🇳🇱".repeat(20));
  expect(limitedText("Mr Pip ", 24)).toBe("Mr Pip ");
});
