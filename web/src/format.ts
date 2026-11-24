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
