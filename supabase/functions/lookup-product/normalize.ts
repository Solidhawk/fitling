/** A shared row of `public.products` as this function writes it (ARCHITECTURE §5.1). */
export type ProductRow = {
  source: 'off';
  source_id: string;
  gtin: string;
  name: Record<string, string>;
  brand: string | null;
  search_name: string;
  quantity_unit: 'g' | 'ml';
  serving_size: number | null;
  kcal_100: number | null;
  protein_100: number | null;
  carbs_100: number | null;
  sugars_100: number | null;
  fat_100: number | null;
  saturated_fat_100: number | null;
  fiber_100: number | null;
  salt_100: number | null;
  image_url: string | null;
  /** True when the energy on the label fits its macros; false when it does not or cannot be checked. */
  is_verified: boolean;
  fetched_at: string;
};

// The same numbers as FoodMath in FitlingCore.
const kilojoulesPerKcal = 4.184;
const inconsistentShare = 0.25;
const inconsistentKcal = 30;

// The same limits as the check constraints on `public.products`.
const limits = {
  kcal: 900,
  grams: 100,
};

/** The languages the app is written in; a name in another language is only used as a last resort. */
const appLanguages = ['nl', 'en', 'de'];

export function kcalFromKilojoules(kilojoules: number): number {
  return kilojoules / kilojoulesPerKcal;
}

export function isConsistent(kcal: number, proteinG: number, carbsG: number, fatG: number): boolean {
  const difference = Math.abs(4 * proteinG + 4 * carbsG + 9 * fatG - kcal);
  return difference <= kcal * inconsistentShare || difference <= inconsistentKcal;
}

/** EAN-8 or EAN-13 with a valid GS1 check digit; UPC-A arrives already padded to 13 digits. */
export function isValidGtin(code: string): boolean {
  if (!/^(\d{8}|\d{13})$/.test(code)) return false;
  const digits = [...code].map(Number);
  const check = digits.pop()!;
  const sum = digits.reverse().reduce((total, digit, index) => total + digit * (index % 2 === 0 ? 3 : 1), 0);
  return (10 - (sum % 10)) % 10 === check;
}

function number(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function roundTo(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

/** A value outside its limit becomes null: a wrong number is worse than a missing one. */
function within(value: number | null, max: number, decimals: number): number | null {
  if (value === null || value < 0 || value > max) return null;
  return roundTo(value, decimals);
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : null;
}

function searchName(names: string[], brand: string | null): string {
  return [...names, ...(brand ? [brand] : [])]
    .join(' ')
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase();
}

const volume = /(^|[\d\s])(ml|cl|dl|l)\s*\)?$/i;

/** A product from the Open Food Facts API as a row for the shared cache, or null without any name. */
export function normalizeOffProduct(product: unknown, gtin: string, fetchedAt: Date): ProductRow | null {
  const p = (product ?? {}) as Record<string, unknown>;
  const nutriments = (p.nutriments ?? {}) as Record<string, unknown>;

  const name: Record<string, string> = {};
  for (const language of appLanguages) {
    const value = text(p[`product_name_${language}`]);
    if (value) name[language] = value;
  }
  if (Object.keys(name).length === 0) {
    const fallback = text(p.product_name);
    const language = text(p.lc) ?? 'en';
    if (fallback) name[language] = fallback;
  }
  if (Object.keys(name).length === 0) return null;

  const brand = text(p.brands);
  const kilojoules = number(nutriments['energy-kj_100g']) ?? number(nutriments['energy_100g']);
  const kcalOnLabel = number(nutriments['energy-kcal_100g']) ??
    (kilojoules === null ? null : kcalFromKilojoules(kilojoules));
  const kcal = within(kcalOnLabel, limits.kcal, 1);
  const grams = (key: string) => within(number(nutriments[key]), limits.grams, 2);
  const protein = grams('proteins_100g');
  const carbs = grams('carbohydrates_100g');
  const fat = grams('fat_100g');

  const unit = text(p.product_quantity_unit) ?? '';
  const serving = text(p.serving_size) ?? '';
  const isVolume = /^(ml|cl|dl|l)$/i.test(unit) || volume.test(serving);
  const servingSize = number(p.serving_quantity);

  return {
    source: 'off',
    source_id: gtin,
    gtin,
    name,
    brand,
    search_name: searchName(Object.values(name), brand),
    quantity_unit: isVolume ? 'ml' : 'g',
    serving_size: servingSize !== null && servingSize > 0 ? roundTo(servingSize, 2) : null,
    kcal_100: kcal,
    protein_100: protein,
    carbs_100: carbs,
    sugars_100: grams('sugars_100g'),
    fat_100: fat,
    saturated_fat_100: grams('saturated-fat_100g'),
    fiber_100: grams('fiber_100g'),
    salt_100: grams('salt_100g'),
    image_url: text(p.image_front_url),
    is_verified: kcal !== null && protein !== null && carbs !== null && fat !== null &&
      isConsistent(kcal, protein, carbs, fat),
    fetched_at: fetchedAt.toISOString(),
  };
}
