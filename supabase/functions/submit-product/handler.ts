import { corsHeaders } from '../delete-account/handler.ts';
import { isValidGtin } from '../lookup-product/normalize.ts';

/**
 * A product a user typed in, or read from the label (TASKS 2.8), shared with everyone for its barcode
 * (ARCHITECTURE §5, step 3). Always unverified: the app asks to check the values of a shared row from a user.
 */
export type SharedRow = {
  source: 'user';
  gtin: string;
  name: Record<string, string>;
  brand: string | null;
  search_name: string;
  quantity_unit: 'g' | 'ml';
  serving_size: number | null;
  kcal_100: number;
  protein_100: number | null;
  carbs_100: number | null;
  sugars_100: number | null;
  fat_100: number | null;
  saturated_fat_100: number | null;
  fiber_100: number | null;
  salt_100: number | null;
  is_verified: false;
};

export type Deps = {
  getUser(token: string): Promise<{ id: string } | null>;
  /** Counts this call; false when the user is over the limit for this hour. */
  consumeRateLimit(userID: string): Promise<boolean>;
  /**
   * The submission, the shared row and its status in one transaction (submit_shared_product in
   * supabase/submit-product.sql): the id of the barcode's shared row, and whether this submission made it.
   */
  submit(userID: string, payload: Submitted, row: SharedRow): Promise<{ productID: string; created: boolean }>;
  log(message: string): void;
};

/** What is kept of a submission: only the fields the app sends, as it sent them. */
export type Submitted = Record<string, string | number>;

/** The languages the app is written in; a name is stored under one of them. */
const languages = ['nl', 'en', 'de'];
/** The database keeps at most this many characters of a name (FoodLog.nameLimit). */
const nameLimit = 200;
/** A brand is shown under the name; longer than this is no brand. */
const brandLimit = 100;
/** The fields the app sends; anything else in the body is not kept. */
const fields = [
  'gtin',
  'name',
  'brand',
  'language',
  'quantityUnit',
  'servingSize',
  'kcal',
  'protein',
  'carbs',
  'sugars',
  'fat',
  'saturatedFat',
  'fiber',
  'salt',
];

function json(status: number, body: unknown): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

/** Lower case, without accents, without white space around it: as FoodLog.searchKey in FitlingCore. */
function searchKey(text: string): string {
  return text.toLowerCase().normalize('NFD').replace(/\p{Mn}/gu, '').trim();
}

/** A number within the check constraint of its column, rounded as the column keeps it; otherwise null. */
function within(value: unknown, max: number, decimals: number): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > max) return null;
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

/** The shared row, or why it cannot be made. */
function sharedRow(body: Record<string, unknown>): SharedRow | null {
  const gtin = typeof body.gtin === 'string' ? body.gtin : '';
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  const kcal = within(body.kcal, 900, 1);
  const brand = typeof body.brand === 'string' && body.brand.trim() !== '' ? body.brand.trim() : null;
  // Counted in characters, as Swift counts them in FitlingCore.
  if (!isValidGtin(gtin) || name === '' || [...name].length > nameLimit || kcal === null) return null;
  if (brand !== null && [...brand].length > brandLimit) return null;
  const language = typeof body.language === 'string' && languages.includes(body.language) ? body.language : 'nl';
  // Rounded first, as numeric(7,2) keeps it: 0.001 would become 0, which the check refuses.
  const servingRounded = typeof body.servingSize === 'number' && Number.isFinite(body.servingSize)
    ? Math.round(body.servingSize * 100) / 100
    : 0;
  const serving = servingRounded > 0 && servingRounded <= 99_999.99 ? servingRounded : null;
  return {
    source: 'user',
    gtin,
    name: { [language]: name },
    brand,
    search_name: searchKey([name, brand].filter((part) => part !== null).join(' ')),
    quantity_unit: body.quantityUnit === 'ml' ? 'ml' : 'g',
    serving_size: serving,
    kcal_100: kcal,
    protein_100: within(body.protein, 100, 2),
    carbs_100: within(body.carbs, 100, 2),
    sugars_100: within(body.sugars, 100, 2),
    fat_100: within(body.fat, 100, 2),
    saturated_fat_100: within(body.saturatedFat, 100, 2),
    fiber_100: within(body.fiber, 100, 2),
    salt_100: within(body.salt, 100, 2),
    is_verified: false,
  };
}

/**
 * Shares a product for a barcode no source knows. The first one becomes the shared row; a barcode that already has
 * one keeps it and the submission waits, except that the user who made a row may correct it and a removed row comes
 * back. `lookup-product` asks Open Food Facts first, so a product that turns up there later replaces a row from a
 * user.
 */
export async function handle(req: Request, deps: Deps): Promise<Response> {
  try {
    return await share(req, deps);
  } catch (error) {
    // With the CORS headers, so the web app sees a server error and not a refused request.
    deps.log(`submit-product: ${String(error)}`);
    return json(500, { error: 'server_error' });
  }
}

/** Only the known fields, each a string or a number: the submission keeps nothing else the body may hold. */
function submitted(body: Record<string, unknown>): Submitted {
  const kept: Submitted = {};
  for (const field of fields) {
    const value = body[field];
    if (typeof value === 'string' || (typeof value === 'number' && Number.isFinite(value))) kept[field] = value;
  }
  return kept;
}

async function share(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders });
  const header = req.headers.get('Authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length).trim() : '';
  if (token === '') return json(401, { error: 'unauthorized' });
  const user = await deps.getUser(token);
  if (user === null) return json(401, { error: 'unauthorized' });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: 'invalid_product' });
  }
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return json(400, { error: 'invalid_product' });
  const row = sharedRow(body as Record<string, unknown>);
  if (row === null) return json(400, { error: 'invalid_product' });

  if (!(await deps.consumeRateLimit(user.id))) return json(429, { error: 'rate_limited' });

  const result = await deps.submit(user.id, submitted(body as Record<string, unknown>), row);
  return json(result.created ? 201 : 200, result);
}
