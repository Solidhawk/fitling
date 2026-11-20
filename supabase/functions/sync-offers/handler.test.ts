import { assertEquals } from '@std/assert';
import { type Deps, handle, syncOffers } from './handler.ts';
import type { OfferRow } from './normalize.ts';
import type { OfferProvider, RawOffer } from './provider.ts';

const now = new Date('2026-11-19T04:00:00Z');
const secret = 'sb_secret_test';

function offer(id: string, overrides: Partial<RawOffer> = {}): RawOffer {
  return {
    externalId: id,
    title: `Product ${id}`,
    priceCents: 100,
    validFrom: '2026-11-16',
    validTo: '2026-11-22',
    ...overrides,
  };
}

function provider(id: string, offers: RawOffer[] | Error): OfferProvider {
  return {
    supermarketId: id,
    supermarketName: id.toUpperCase(),
    fetchOffers: () => offers instanceof Error ? Promise.reject(offers) : Promise.resolve({ offers, more: false }),
  };
}

function call(query: string, providers: OfferProvider[], d: Deps = deps()): Promise<Response> {
  return handle(
    new Request(`http://localhost/sync-offers${query}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${secret}` },
    }),
    secret,
    providers,
    d,
  );
}

/** A provider that records which part it was asked for. */
function partedProvider(id: string, asked: number[]): OfferProvider {
  return {
    supermarketId: id,
    supermarketName: id.toUpperCase(),
    fetchOffers: (part) => {
      asked.push(part);
      return Promise.resolve({ offers: [offer(`${id}-${part}`)], more: true });
    },
  };
}

type Recorder = Deps & { supermarkets: string[]; rows: OfferRow[]; removedBefore: string[]; logs: string[] };

function deps(overrides: Partial<Deps> = {}): Recorder {
  const recorder: Recorder = {
    supermarkets: [],
    rows: [],
    removedBefore: [],
    logs: [],
    upsertSupermarket: (id) => {
      recorder.supermarkets.push(id);
      return Promise.resolve();
    },
    upsertOffers: (rows) => {
      recorder.rows.push(...rows);
      return Promise.resolve();
    },
    removeExpired: (before) => {
      recorder.removedBefore.push(before);
      return Promise.resolve(3);
    },
    now: () => now,
    log: (message) => {
      recorder.logs.push(message);
    },
  };
  return Object.assign(recorder, overrides);
}

Deno.test('every provider is fetched and its offers are stored under its supermarket', async () => {
  const d = deps();
  const result = await syncOffers([provider('a', [offer('1'), offer('2')]), provider('b', [offer('3')])], d);
  assertEquals(d.supermarkets, ['a', 'b']);
  assertEquals(d.rows.map((r) => `${r.supermarket_id}:${r.external_id}`), ['a:1', 'a:2', 'b:3']);
  assertEquals(result.providers, [
    { supermarketId: 'a', stored: 2, skipped: 0, more: false },
    { supermarketId: 'b', stored: 1, skipped: 0, more: false },
  ]);
});

Deno.test('a provider that fails does not stop the others', async () => {
  const d = deps();
  const result = await syncOffers([provider('a', new Error('timeout')), provider('b', [offer('3')])], d);
  assertEquals(d.rows.map((r) => r.supermarket_id), ['b']);
  assertEquals(result.providers[0], { supermarketId: 'a', stored: 0, skipped: 0, more: false, error: 'timeout' });
  assertEquals(d.logs, ['sync-offers: a failed: timeout']);
});

Deno.test('a failed write for one provider does not stop the others', async () => {
  const d = deps({
    upsertOffers: (rows) => rows[0].supermarket_id === 'a' ? Promise.reject(new Error('conflict')) : Promise.resolve(),
  });
  const result = await syncOffers([provider('a', [offer('1')]), provider('b', [offer('3')])], d);
  assertEquals(result.providers.map((p) => p.error ?? 'ok'), ['conflict', 'ok']);
});

Deno.test('offers the table would refuse are counted as skipped', async () => {
  const d = deps();
  const result = await syncOffers([provider('a', [offer('1'), offer('2', { priceCents: -1 })])], d);
  assertEquals(result.providers[0], { supermarketId: 'a', stored: 1, skipped: 1, more: false });
});

Deno.test('the same offer twice from one source is stored once', async () => {
  const d = deps();
  await syncOffers([provider('a', [offer('1'), offer('1', { priceCents: 90 })])], d);
  assertEquals(d.rows.map((r) => r.price_cents), [90]);
});

Deno.test('offers that ended more than a week ago are removed', async () => {
  const d = deps();
  const result = await syncOffers([], d);
  assertEquals(d.removedBefore, ['2026-11-12']);
  assertEquals(result.removed, 3);
});

Deno.test('only a call with the secret key runs the job', async () => {
  const d = deps();
  const callWith = (auth?: string) =>
    handle(
      new Request('http://localhost/sync-offers?retailer=a', {
        method: 'POST',
        headers: auth ? { Authorization: auth } : {},
      }),
      secret,
      [provider('a', [])],
      d,
    );
  assertEquals((await callWith()).status, 401);
  assertEquals((await callWith('Bearer sb_publishable_x')).status, 401);
  const ok = await callWith(`Bearer ${secret}`);
  assertEquals(ok.status, 200);
  assertEquals((await ok.json()).removed, 3);
});

Deno.test('a call without a chain is refused: all chains in one call would pass every limit', async () => {
  const asked: number[] = [];
  const response = await call('', [partedProvider('a', asked), partedProvider('b', asked)]);
  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: 'retailer_required' });
  assertEquals(asked, []);
});

Deno.test('a call can name the chains to fetch, so one run stays within the limits', async () => {
  const d = deps();
  const response = await call('?retailer=b', [provider('a', [offer('1')]), provider('b', [offer('2')])], d);
  assertEquals((await response.json()).providers.map((p: { supermarketId: string }) => p.supermarketId), ['b']);
  assertEquals(d.supermarkets, ['b']);
});

Deno.test('a chain that is not known is refused', async () => {
  const response = await call('?retailer=nope', [provider('a', [offer('1')])]);
  assertEquals(response.status, 400);
});

Deno.test('a call can ask for a later part of a large chain, and hears whether more is left', async () => {
  const asked: number[] = [];
  const d = deps();
  const response = await call('?retailer=a&part=3', [partedProvider('a', asked)], d);
  assertEquals(asked, [3]);
  assertEquals(d.rows.map((r) => r.external_id), ['a-3']);
  assertEquals((await response.json()).providers, [{ supermarketId: 'a', stored: 1, skipped: 0, more: true }]);
});

Deno.test('without a part the first part is fetched', async () => {
  const asked: number[] = [];
  await call('?retailer=a', [partedProvider('a', asked)]);
  assertEquals(asked, [1]);
});

Deno.test('a part that is not a whole number from 1 is refused', async () => {
  for (const part of ['0', '-1', '1.5', 'x', '']) {
    const asked: number[] = [];
    const response = await call(`?retailer=a&part=${part}`, [partedProvider('a', asked)]);
    assertEquals(response.status, 400, part);
    assertEquals(await response.json(), { error: 'bad_part' }, part);
    assertEquals(asked, [], part);
  }
});
