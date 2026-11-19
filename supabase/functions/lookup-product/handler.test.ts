import { assertEquals } from '@std/assert';
import { type Deps, handle, type StoredProduct } from './handler.ts';
import type { ProductRow } from './normalize.ts';
import { SourceUnavailable } from './openfoodfacts.ts';

const fixture = JSON.parse(await Deno.readTextFile(new URL('./fixtures/off-8712100849084.json', import.meta.url)));
const gtin = '8712100849084';
const now = new Date('2026-11-19T12:00:00Z');
const daysAgo = (days: number) => new Date(now.getTime() - days * 86_400_000).toISOString();

type Recorder = Deps & { sourceCalls: number; stored: Map<string, StoredProduct>; allowed: number };

function deps(overrides: Partial<Deps> = {}): Recorder {
  const recorder: Recorder = {
    sourceCalls: 0,
    stored: new Map(),
    allowed: 60,
    getUser: (token) => Promise.resolve(token === 'valid-token' ? { id: 'user-1' } : null),
    consumeRateLimit: () => {
      recorder.allowed -= 1;
      return Promise.resolve(recorder.allowed >= 0);
    },
    findShared: (code) => Promise.resolve(recorder.stored.get(code) ?? null),
    fetchOff: () => {
      recorder.sourceCalls += 1;
      return Promise.resolve(fixture.product);
    },
    // Like the database function: one shared row per barcode, updated in place.
    storeShared: (row: ProductRow) => {
      const existing = recorder.stored.get(row.gtin);
      const stored = { ...row, id: existing?.id ?? crypto.randomUUID() };
      recorder.stored.set(row.gtin, stored);
      return Promise.resolve(stored);
    },
    now: () => now,
    log: () => {},
  };
  return Object.assign(recorder, overrides);
}

function request(body: unknown, token: string | null = 'valid-token'): Request {
  const headers = new Headers({ 'Content-Type': 'application/json' });
  if (token !== null) headers.set('Authorization', `Bearer ${token}`);
  return new Request('http://localhost/lookup-product', { method: 'POST', headers, body: JSON.stringify(body) });
}

function cached(fetchedAt: string, kcal = 300): StoredProduct {
  return {
    id: 'product-1',
    source: 'off',
    source_id: gtin,
    gtin,
    name: { nl: 'Oud' },
    brand: null,
    search_name: 'oud',
    quantity_unit: 'g',
    serving_size: null,
    kcal_100: kcal,
    protein_100: null,
    carbs_100: null,
    sugars_100: null,
    fat_100: null,
    saturated_fat_100: null,
    fiber_100: null,
    salt_100: null,
    image_url: null,
    is_verified: false,
    fetched_at: fetchedAt,
  };
}

Deno.test('a request without a valid token is rejected', async () => {
  assertEquals((await handle(request({ gtin }, null), deps())).status, 401);
  assertEquals((await handle(request({ gtin }, 'other-token'), deps())).status, 401);
});

Deno.test('rejects a wrong check digit', async () => {
  const d = deps();
  const response = await handle(request({ gtin: '8712100849085' }), d);
  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: 'invalid_gtin' });
  assertEquals(d.sourceCalls, 0);
});

Deno.test('returns the cached product without calling the source', async () => {
  const d = deps();
  d.stored.set(gtin, cached(daysAgo(29)));
  const response = await handle(request({ gtin }), d);
  assertEquals(response.status, 200);
  assertEquals((await response.json()).name, { nl: 'Oud' });
  assertEquals(d.sourceCalls, 0);
});

Deno.test('refreshes a product older than thirty days', async () => {
  const d = deps();
  d.stored.set(gtin, cached(daysAgo(31)));
  const response = await handle(request({ gtin }), d);
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(d.sourceCalls, 1);
  assertEquals(body.id, 'product-1');
  assertEquals(body.kcal_100, 338);
  assertEquals(body.fetched_at, now.toISOString());
});

Deno.test('stores a new product once, also when two calls arrive together', async () => {
  const d = deps();
  const [first, second] = await Promise.all([handle(request({ gtin }), d), handle(request({ gtin }), d)]);
  assertEquals([first.status, second.status], [200, 200]);
  assertEquals(d.stored.size, 1);
  assertEquals((await first.json()).id, (await second.json()).id);
});

Deno.test('an unknown product is 404 and nothing is stored', async () => {
  const d = deps({ fetchOff: () => Promise.resolve(null) });
  const response = await handle(request({ gtin }), d);
  assertEquals(response.status, 404);
  assertEquals(await response.json(), { error: 'not_found' });
  assertEquals(d.stored.size, 0);
});

Deno.test('an unreachable source is 502 without a cached row', async () => {
  const d = deps({ fetchOff: () => Promise.reject(new SourceUnavailable('503 three times')) });
  const response = await handle(request({ gtin }), d);
  assertEquals(response.status, 502);
  assertEquals(await response.json(), { error: 'source_unavailable' });
});

Deno.test('an unreachable source gives the old cached row rather than nothing', async () => {
  const d = deps({ fetchOff: () => Promise.reject(new SourceUnavailable('503 three times')) });
  d.stored.set(gtin, cached(daysAgo(40)));
  const response = await handle(request({ gtin }), d);
  assertEquals(response.status, 200);
  assertEquals((await response.json()).name, { nl: 'Oud' });
});

Deno.test('limits calls per user per hour', async () => {
  const d = deps();
  d.allowed = 1;
  assertEquals((await handle(request({ gtin }), d)).status, 200);
  const limited = await handle(request({ gtin }), d);
  assertEquals(limited.status, 429);
  assertEquals(await limited.json(), { error: 'rate_limited' });
});
