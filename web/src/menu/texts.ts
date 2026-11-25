import type { Goal, IsoDay, MenuIssue } from "../core/fitlingCore";
import { language, t } from "../i18n";

/** Up to two decimals, as .number.precision(.fractionLength(0...2)). */
function upToTwo(value: number): string {
  return new Intl.NumberFormat(language(), { maximumFractionDigits: 2 }).format(value);
}

/**
 * An ingredient's amount (ShoppingAmount.text): grams and millilitres with their symbol, spoons and pieces in words.
 * The number is text, so the singular is chosen here: in Dutch, English and German only exactly 1 is singular.
 */
export function amountText(quantity: number, unit: string): string {
  const shown = Math.round(quantity * 100) / 100;
  const value = upToTwo(shown);
  switch (unit) {
    case "g":
      return `${value} g`;
    case "ml":
      return `${value} ml`;
    case "tbsp":
      return t("menu.unit.tbsp %@", value);
    case "tsp":
      return t("menu.unit.tsp %@", value);
    default:
      return shown === 1 ? t("menu.unit.piece.one %@", value) : t("menu.unit.piece %@", value);
  }
}

/** "1 portie · 512 kcal" but "1,5 porties": the servings are text, so the plural is chosen by the amount. */
export function entryDetail(servings: number, energy: number): string {
  const amount = upToTwo(servings);
  return servings <= 1 ? t("menu.entry.detail.one %@ %lld", amount, energy) : t("menu.entry.detail.other %@ %lld", amount, energy);
}

function date(day: IsoDay): Date {
  const [year, month, dayOfMonth] = day.split("-").map(Number);
  return new Date(year, month - 1, dayOfMonth);
}

/** "Dinsdag 24 november": the weekday with its date, starting with a capital as a heading. */
export function dayHeading(day: IsoDay): string {
  const lang = language();
  const text = new Intl.DateTimeFormat(lang, { weekday: "long", day: "numeric", month: "long" }).format(date(day));
  return text.charAt(0).toLocaleUpperCase(lang) + text.slice(1);
}

function weekday(day: IsoDay): string {
  return new Intl.DateTimeFormat(language(), { weekday: "long" }).format(date(day));
}

/** What the planner could not solve, in a sentence (MenuIssue.text). */
export function issueText(issue: MenuIssue): string {
  switch (issue.kind) {
    case "noRecipes":
      return t("menu.issue.noRecipes %@", t(`meal.${issue.slot ?? "dinner"}`));
    case "kcalOutOfRange":
      return t("menu.issue.kcal %@ %lld", weekday(issue.day ?? ""), issue.kcal ?? 0);
    case "proteinShort":
      return t("menu.issue.protein %@ %lld", weekday(issue.day ?? ""), issue.missingG ?? 0);
    case "overBudget":
      return t("menu.issue.budget %@", new Intl.NumberFormat(language(), { style: "currency", currency: "EUR" }).format((issue.byCents ?? 0) / 100));
  }
}

/** The steps in the first of the user's languages that has them, then English or Dutch, then any (RecipeDetailView). */
export function recipeSteps(steps: Record<string, string[]>, languages: readonly string[] = navigator.languages): string[] {
  for (const lang of [...languages.map((tag) => tag.slice(0, 2).toLowerCase()), "en", "nl"]) {
    if (steps[lang]?.length) return steps[lang];
  }
  return Object.values(steps)[0] ?? [];
}

/** The energy of a recipe per serving and its time, for a list row (RecipeRow). */
export function recipeDetail(kcalPerServing: number, cookMinutes: number): string {
  return t("menu.recipe.detail %lld %lld", Math.round(kcalPerServing), cookMinutes);
}

/** What the user chose for a menu (MenuOptions): how many days from today, and a goal other than the daily target. */
export interface MenuOptions {
  days: number;
  goal?: Goal;
}

/** Today and the six days after it (MenuStore.menuDays). */
export const menuDays = 7;

const optionsKey = "fitling.menuOptions";
const goals: Goal[] = ["lose", "build_muscle", "maintain", "recomp"];

/** The choices of the last menu on this device; the generator opens with them and renewing a day uses the goal. */
export function rememberedMenuOptions(): MenuOptions {
  try {
    const stored = JSON.parse(localStorage.getItem(optionsKey) ?? "null") as { days?: unknown; goal?: unknown } | null;
    const days = stored?.days;
    if (typeof days !== "number" || !Number.isInteger(days) || days < 1 || days > menuDays) return { days: menuDays };
    const goal = goals.find((candidate) => candidate === stored?.goal);
    if (stored?.goal !== undefined && !goal) return { days: menuDays };
    return goal ? { days, goal } : { days };
  } catch {
    return { days: menuDays };
  }
}

export function rememberMenuOptions(options: MenuOptions) {
  try {
    localStorage.setItem(optionsKey, JSON.stringify(options));
  } catch {
    // Private mode: the choice holds for this visit only.
  }
}
