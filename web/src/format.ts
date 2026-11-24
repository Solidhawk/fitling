import { language } from "./i18n";

// Numbers as the app shows them through Measurement and .formatted: in the user's language, abbreviated units.

export function kcal(value: number): string {
  return new Intl.NumberFormat(language(), { style: "unit", unit: "kilocalorie", unitDisplay: "short", maximumFractionDigits: 0 }).format(value);
}

export function grams(value: number): string {
  return new Intl.NumberFormat(language(), { style: "unit", unit: "gram", unitDisplay: "short", maximumFractionDigits: 0 }).format(value);
}

export function percent(share: number): string {
  return new Intl.NumberFormat(language(), { style: "percent", maximumFractionDigits: 0 }).format(share);
}

export function decimal(value: number, fractionDigits = 1): string {
  return new Intl.NumberFormat(language(), { maximumFractionDigits: fractionDigits }).format(value);
}

/** A number as typed, with a comma or a point; empty or unreadable is nothing. */
export function parseNumber(text: string): number | undefined {
  if (text.trim() === "") return undefined;
  const value = Number(text.replace(",", "."));
  return Number.isFinite(value) ? value : undefined;
}

/** With exactly `digits` decimals, as .number.precision(.fractionLength(digits)). */
export function fixed(value: number, digits: number): string {
  return new Intl.NumberFormat(language(), { minimumFractionDigits: digits, maximumFractionDigits: digits }).format(value);
}
