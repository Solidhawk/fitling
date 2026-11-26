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
  /** Keeps what was sent, as it was sent, and returns its id. */
  storeSubmission(userID: string, gtin: string, payload: unknown): Promise<string>;
  findShared(gtin: string): Promise<{ id: string } | null>;
  /** The new shared row's id; null when another one for this barcode was just made (the unique index). */
  insertShared(row: SharedRow): Promise<string | null>;
  markAccepted(submissionID: string, productID: string): Promise<void>;
};

/** The languages the app is written in; a name is stored under one of them. */
const languages = ['nl', 'en', 'de'];
/** The database keeps at most this many characters of a name (FoodLog.nameLimit). */
const nameLimit = 200;

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
  if (!isValidGtin(gtin) || name === '' || name.length > nameLimit || kcal === null) return null;
  const brand = typeof body.brand === 'string' && body.brand.trim() !== '' ? body.brand.trim() : null;
  const language = typeof body.language === 'string' && languages.includes(body.language) ? body.language : 'nl';
  const serving = typeof body.servingSize === 'number' && body.servingSize > 0 && body.servingSize < 100_000
    ? Math.round(body.servingSize * 100) / 100
    : null;
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
 * one keeps it, and the submission waits as it was sent. `lookup-product` asks Open Food Facts first, so a product
 * that turns up there later replaces a row from a user.
 */
export async function handle(req: Request, deps: Deps): Promise<Response> {
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

  const submissionID = await deps.storeSubmission(user.id, row.gtin, body);
  const existing = await deps.findShared(row.gtin);
  if (existing) return json(200, { productID: existing.id, created: false });
  const productID = await deps.insertShared(row);
  if (productID === null) {
    const first = await deps.findShared(row.gtin);
    if (first) return json(200, { productID: first.id, created: false });
    throw new Error('the shared row was refused, and no other one exists');
  }
  await deps.markAccepted(submissionID, productID);
  return json(201, { productID, created: true });
}
