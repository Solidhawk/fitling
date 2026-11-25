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

/** Uncertain offers the user said are right, kept on this device only (ShoppingViewModel.confirmed). */
export function confirmedOffers(): string[] {
  try {
    const stored: unknown = JSON.parse(localStorage.getItem(confirmedKey) ?? "[]");
    return Array.isArray(stored) ? stored.filter((id): id is string => typeof id === "string") : [];
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
