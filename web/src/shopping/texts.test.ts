import { beforeEach, expect, test, vi } from "vitest";
import { confirmedOffers, confirmOffers, euros, shopList, validUntil } from "./texts";

// The Dutch forms, whatever language runs the tests.
beforeEach(() => {
  vi.stubGlobal("navigator", { languages: ["nl-NL"] });
  return () => vi.unstubAllGlobals();
});

// .currency(code: "EUR") in Dutch, with the no-break space.
test("a price", () => {
  expect(euros(69)).toBe("€ 0,69");
  expect(euros(1250)).toBe("€ 12,50");
});

// "t/m 27 nov": a price is only shown with the day its offer runs to (ShoppingListView.validUntil). The abbreviation
// is the platform's own; some versions of its data end it with a full stop.
test("the last day of an offer", () => {
  expect(validUntil("2026-11-27")).toMatch(/^t\/m 27 nov\.?$/);
});

// .formatted(.list(type: .and)): the shops of a possible offer.
test("the shops of a possible offer", () => {
  expect(shopList(["Proefsuper", "Testmarkt"])).toBe("Bij Proefsuper en Testmarkt");
  expect(shopList(["Proefsuper"])).toBe("Bij Proefsuper");
});

// ShoppingViewModel.confirmed: uncertain offers the user said are right, kept on this device.
test("confirmed offers are remembered", () => {
  const stored = new Map<string, string>();
  vi.stubGlobal("localStorage", { getItem: (key: string) => stored.get(key) ?? null, setItem: (key: string, value: string) => stored.set(key, value) });
  const [a, b, c] = ["00000000-0000-4000-8000-00000000000a", "00000000-0000-4000-8000-00000000000b", "00000000-0000-4000-8000-00000000000c"];
  expect(confirmedOffers()).toEqual([]);
  confirmOffers([b, a]);
  confirmOffers([a, c]);
  expect(confirmedOffers()).toEqual([a, b, c]);
  stored.set("fitling.confirmedOffers", JSON.stringify([a, "not-an-id", 7]));
  expect(confirmedOffers()).toEqual([a]);
  stored.set("fitling.confirmedOffers", "{broken");
  expect(confirmedOffers()).toEqual([]);
});
