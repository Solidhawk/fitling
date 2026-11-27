/**
 * Centimetres and kilograms, or feet, inches and pounds, as Locale.measurementSystem decides on iOS: the US,
 * Liberia and Myanmar use US units, the United Kingdom its own (also feet, inches and pounds in the app).
 */
export function usesMetric(languages: readonly string[] = navigator.languages): boolean {
  const tag = languages[0] ?? "nl-NL";
  let region: string | undefined;
  try {
    region = new Intl.Locale(tag).maximize().region;
  } catch {
    region = undefined;
  }
  return !["US", "LR", "MM", "GB"].includes(region ?? "");
}

/** One pound in kilograms, by definition. */
export const kilogramsPerPound = 0.45359237;

/** Pounds for training weights only in the US system (WeightUnit on iOS); the United Kingdom lifts in kilograms. */
export function usesPounds(languages: readonly string[] = navigator.languages): boolean {
  const tag = languages[0] ?? "nl-NL";
  let region: string | undefined;
  try {
    region = new Intl.Locale(tag).maximize().region;
  } catch {
    region = undefined;
  }
  return ["US", "LR", "MM"].includes(region ?? "");
}
