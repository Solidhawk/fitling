import { isValidGtin, normalizeOffProduct, type ProductRow } from './normalize.ts';
import { SourceUnavailable } from './openfoodfacts.ts';

export type StoredProduct = ProductRow & { id: string };

export type Deps = {
  getUser(token: string): Promise<{ id: string } | null>;
  /** Counts this call; false when the user is over the limit for this hour. */
  consumeRateLimit(userID: string): Promise<boolean>;
  findShared(gtin: string): Promise<StoredProduct | null>;
  /** Throws `SourceUnavailable` when Open Food Facts cannot be reached. */
  fetchOff(gtin: string): Promise<unknown | null>;
  /** Inserts or updates the one shared row for this barcode and returns it. */
  storeShared(row: ProductRow): Promise<StoredProduct>;
  now(): Date;
  log(message: string): void;
};

/** A cached product is used as it is for this long; after that the source is asked again. */
const freshForMs = 30 * 24 * 60 * 60 * 1000;

function json(status: number, body: unknown): Response {
  return Response.json(body, { status });
}

async function requestedGtin(req: Request): Promise<string | null> {
  try {
    const body = await req.json();
    return typeof body?.gtin === 'string' ? body.gtin : null;
  } catch {
    return null;
  }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const header = req.headers.get('Authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length).trim() : '';
  if (token === '') return json(401, { error: 'unauthorized' });
  const user = await deps.getUser(token);
  if (user === null) return json(401, { error: 'unauthorized' });

  const gtin = await requestedGtin(req);
  if (gtin === null || !isValidGtin(gtin)) return json(400, { error: 'invalid_gtin' });

  if (!(await deps.consumeRateLimit(user.id))) return json(429, { error: 'rate_limited' });

  const cached = await deps.findShared(gtin);
  const now = deps.now();
  if (cached && now.getTime() - new Date(cached.fetched_at).getTime() < freshForMs) {
    return json(200, cached);
  }

  let product: unknown | null;
  try {
    product = await deps.fetchOff(gtin);
  } catch (error) {
    if (!(error instanceof SourceUnavailable)) throw error;
    deps.log(`source_unavailable: ${error.message}`);
    // An old row is better than nothing; the app keeps its own copy for the same reason.
    return cached ? json(200, cached) : json(502, { error: 'source_unavailable' });
  }

  // Nothing is stored for an unknown barcode, so a product added to the source tomorrow works tomorrow.
  const row = product === null ? null : normalizeOffProduct(product, gtin, now);
  if (row === null) return cached ? json(200, cached) : json(404, { error: 'not_found' });

  return json(200, await deps.storeShared(row));
}
