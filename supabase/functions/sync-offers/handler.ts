import { type OfferRow, offerRow } from './normalize.ts';
import type { OfferProvider } from './provider.ts';

export type Deps = {
  upsertSupermarket(id: string, name: string): Promise<void>;
  /** Upsert on (supermarket_id, external_id, valid_from). */
  upsertOffers(rows: OfferRow[]): Promise<void>;
  /** Deletes offers whose valid_to is before this date; returns how many. */
  removeExpired(before: string): Promise<number>;
  now(): Date;
  log(message: string): void;
};

/** `more`: a later part of this chain still has offers, so the scheduler must call that part too. */
export type ProviderResult = { supermarketId: string; stored: number; skipped: number; more: boolean; error?: string };
export type SyncResult = { providers: ProviderResult[]; removed: number };

/** Offers that ended this many days ago are removed. */
const keepDays = 7;

function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function syncProvider(provider: OfferProvider, part: number, deps: Deps): Promise<ProviderResult> {
  const result: ProviderResult = { supermarketId: provider.supermarketId, stored: 0, skipped: 0, more: false };
  try {
    const { offers, more } = await provider.fetchOffers(part);
    result.more = more;
    const fetchedAt = deps.now();
    // One row per key: a source that lists an offer twice would make the upsert fail.
    const rows = new Map<string, OfferRow>();
    for (const offer of offers) {
      const row = offerRow(offer, provider.supermarketId, fetchedAt);
      if (row === null) {
        result.skipped += 1;
        continue;
      }
      rows.set(`${row.external_id}\u0000${row.valid_from}`, row);
    }
    await deps.upsertSupermarket(provider.supermarketId, provider.supermarketName);
    if (rows.size > 0) await deps.upsertOffers([...rows.values()]);
    result.stored = rows.size;
  } catch (error) {
    result.error = message(error);
    deps.log(`sync-offers: ${provider.supermarketId} failed: ${result.error}`);
  }
  return result;
}

/** Fetches every provider in turn; one that fails does not stop the others (ARCHITECTURE §6). */
export async function syncOffers(providers: OfferProvider[], deps: Deps, part = 1): Promise<SyncResult> {
  const results: ProviderResult[] = [];
  for (const provider of providers) results.push(await syncProvider(provider, part, deps));
  const cutoff = new Date(deps.now().getTime() - keepDays * 86_400_000).toISOString().slice(0, 10);
  const removed = await deps.removeExpired(cutoff);
  return { providers: results, removed };
}

/**
 * The job runs only when called with the project's secret key: by the scheduler, never by the app.
 * `?retailer=jumbo,lidl` (required) names the chains of a run and `&part=2` asks for their second part, so one
 * call stays within the limits of an Edge Function; the scheduler calls once per chain and part.
 */
export async function handle(
  req: Request,
  secretKey: string,
  providers: OfferProvider[],
  deps: Deps,
): Promise<Response> {
  if (req.headers.get('Authorization') !== `Bearer ${secretKey}`) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }
  const params = new URL(req.url).searchParams;
  const asked = params.get('part');
  const part = asked === null ? 1 : Number(asked);
  if (!Number.isInteger(part) || part < 1) {
    return Response.json({ error: 'bad_part' }, { status: 400 });
  }
  // All 20 chains in one call is over 100 pages: past the CPU and time limits of an Edge Function.
  const named = params.get('retailer')?.split(',').map((id) => id.trim()).filter(Boolean) ?? [];
  if (named.length === 0) return Response.json({ error: 'retailer_required' }, { status: 400 });
  const chosen = providers.filter((provider) => named.includes(provider.supermarketId));
  if (chosen.length !== named.length) {
    return Response.json({ error: 'unknown_retailer' }, { status: 400 });
  }
  return Response.json(await syncOffers(chosen, deps, part));
}
