/** Open Food Facts could not be reached, also after the retries. */
export class SourceUnavailable extends Error {}

export type OffDeps = {
  fetch: (input: string, init?: RequestInit) => Promise<Response>;
  sleep: (ms: number) => Promise<void>;
  /** Open Food Facts asks every app to name itself and a contact address. */
  userAgent: string;
};

const fields = [
  'code',
  'lc',
  'product_name',
  'product_name_nl',
  'product_name_en',
  'product_name_de',
  'brands',
  'product_quantity_unit',
  'serving_size',
  'serving_quantity',
  'image_front_url',
  'nutriments',
].join(',');

/** Waits before each retry (ARCHITECTURE §5): three retries after the first attempt. */
const retryWaits = [1000, 2000, 4000];
const timeoutMs = 5000;

/** The product, or null when Open Food Facts does not know the barcode. */
export async function fetchOffProduct(gtin: string, deps: OffDeps): Promise<unknown | null> {
  const url = `https://world.openfoodfacts.org/api/v2/product/${gtin}?fields=${fields}`;
  for (let attempt = 0; attempt <= retryWaits.length; attempt++) {
    if (attempt > 0) await deps.sleep(retryWaits[attempt - 1]);
    let response: Response;
    try {
      response = await deps.fetch(url, {
        headers: { 'User-Agent': deps.userAgent, Accept: 'application/json' },
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch {
      // A network error or the timeout: try again.
      continue;
    }
    if (response.status === 404) {
      await response.body?.cancel();
      return null;
    }
    if (response.status >= 500 || response.status === 429) {
      await response.body?.cancel();
      continue;
    }
    if (!response.ok) {
      await response.body?.cancel();
      throw new SourceUnavailable(`open food facts answered ${response.status}`);
    }
    const body = await response.json();
    return body?.status === 1 && body.product ? body.product : null;
  }
  throw new SourceUnavailable(`open food facts unavailable after ${retryWaits.length + 1} attempts`);
}
