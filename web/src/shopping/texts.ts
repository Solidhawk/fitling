import type { IsoDay } from "../core/fitlingCore";
import { language, t } from "../i18n";

/** A price, as .currency(code: "EUR") in the user's language. */
export function euros(cents: number): string {
  return new Intl.NumberFormat(language(), { style: "currency", currency: "EUR" }).format(cents / 100);
}

/** "t/m 27 nov": the day an offer runs to, as .dateTime.day().month(.abbreviated), in the platform's own words. */
export function validUntil(day: IsoDay): string {
  const [year, month, date] = day.split("-").map(Number);
  const shown = new Intl.DateTimeFormat(language(), { day: "numeric", month: "short" }).format(new Date(year, month - 1, date));
  return t("shopping.offer.until %@", shown);
}

/** "Bij Proefsuper en Testmarkt": the shops of a possible offer, as .list(type: .and). */
export function shopList(names: string[]): string {
  return t("shopping.uncertain.shops %@", new Intl.ListFormat(language(), { type: "conjunction" }).format(names));
}

const confirmedKey = "fitling.confirmedOffers";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Uncertain offers the user said are right, kept on this device only (ShoppingViewModel.confirmed). Anything that is no
 * id is left out, as compactMap(UUID.init) on iOS: the rules would refuse the whole list for it.
 */
export function confirmedOffers(): string[] {
  try {
    const stored: unknown = JSON.parse(localStorage.getItem(confirmedKey) ?? "[]");
    return Array.isArray(stored) ? stored.filter((id): id is string => typeof id === "string" && uuid.test(id)) : [];
  } catch {
    return [];
  }
}

export function confirmOffers(ids: string[]) {
  try {
    localStorage.setItem(confirmedKey, JSON.stringify([...new Set([...confirmedOffers(), ...ids])].sort()));
  } catch {
    // Private mode: the answer holds for this visit only.
  }
}

/** The list the user last had open on this device: the list they joined shows, not their own empty one (UNFORGET S47). */
function openListKey(userID: string): string {
  return `fitling.shoppingList.${userID}`;
}

export function rememberedList(userID: string): string | undefined {
  try {
    const stored = localStorage.getItem(openListKey(userID)) ?? "";
    return uuid.test(stored) ? stored : undefined;
  } catch {
    return undefined;
  }
}

/** Without a list, the next opening takes the first by name again (after leaving). */
export function rememberList(userID: string, listID?: string) {
  try {
    if (listID) localStorage.setItem(openListKey(userID), listID);
    else localStorage.removeItem(openListKey(userID));
  } catch {
    // Private mode: the list holds for this visit only.
  }
}
