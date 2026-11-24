import { expect, test } from "vitest";
import { isPlausibleEmail, normalizedEmail } from "./credentials";

test("an email address as the app accepts it", () => {
  expect(isPlausibleEmail(" jan@voorbeeld.nl ")).toBe(true);
  expect(isPlausibleEmail("jan@voorbeeld")).toBe(false);
  expect(isPlausibleEmail("jan@voorbeeld.")).toBe(false);
  expect(isPlausibleEmail("@voorbeeld.nl")).toBe(false);
  expect(isPlausibleEmail("jan@@voorbeeld.nl")).toBe(false);
  expect(normalizedEmail("  jan@voorbeeld.nl\n")).toBe("jan@voorbeeld.nl");
});
