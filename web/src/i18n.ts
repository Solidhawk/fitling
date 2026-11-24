import catalog from "./generated/strings.json";

export type Language = "nl" | "en" | "de";

type Entry = string | { one: string; other: string };
const strings = catalog as Record<Language, Record<string, Entry>>;

/** The first of the browser's languages that Fitling speaks; otherwise Dutch, the catalogue's own language. */
export function language(preferred: readonly string[] = navigator.languages): Language {
  for (const tag of preferred) {
    const base = tag.toLowerCase().split("-")[0];
    if (base === "nl" || base === "en" || base === "de") return base;
  }
  return "nl";
}

/**
 * The text for `key` with its placeholders filled, as String(localized:) does on iOS: `%@` and `%lld`, also
 * numbered (`%2$lld`). A plural is chosen by the first number. An unknown key is shown as it is.
 */
export function translate(lang: Language, key: string, ...args: (string | number)[]): string {
  const entry = strings[lang][key] ?? key;
  const count = args.find((arg): arg is number => typeof arg === "number");
  const text =
    typeof entry === "string"
      ? entry
      : count !== undefined && new Intl.PluralRules(lang).select(count) === "one"
        ? entry.one
        : entry.other;
  const numbers = new Intl.NumberFormat(lang);
  let next = 0;
  return text.replace(/%(?:(\d+)\$)?(lld|@)/g, (placeholder, position: string | undefined) => {
    const arg = args[position ? Number(position) - 1 : next++];
    if (arg === undefined) return placeholder;
    return typeof arg === "number" ? numbers.format(arg) : arg;
  });
}

/** The text in the browser's language. */
export function t(key: string, ...args: (string | number)[]): string {
  return translate(language(), key, ...args);
}
