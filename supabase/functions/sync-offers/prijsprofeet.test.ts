import { assertEquals, assertRejects } from '@std/assert';
import {
  chains,
  parseQuantity,
  type PrijsProfeetProduct,
  PrijsProfeetProvider,
  prijsProfeetProviders,
  toRawOffer,
} from './prijsprofeet.ts';

const product: PrijsProfeetProduct = {
  product_id: 'ah-123-2026-11-17',
  name: 'Halfvolle melk',
  brand: 'AH',
  ean: '8718452345678',
  image_url: 'https://example.test/melk.jpg',
  price: 0.99,
  original_price: 1.25,
  quantity: '1 l',
  retailer: 'albert_heijn',
  is_promotional: true,
  promotion_type: 'percentage',
  promotion_status: 'active',
  promotional_keywords: ['25% korting'],
  valid_from: '2026-11-17',
  valid_until: '2026-11-23',
};

Deno.test('a promotion becomes an offer', () => {
  assertEquals(toRawOffer(product), {
    externalId: 'ah-123-2026-11-17',
    title: 'Halfvolle melk',
    brand: 'AH',
    gtin: '8718452345678',
    quantityValue: 1000,
    quantityUnit: 'ml',
    priceCents: 99,
    regularPriceCents: 125,
    promoLabel: '25% korting',
    validFrom: '2026-11-17',
    validTo: '2026-11-23',
    imageUrl: 'https://example.test/melk.jpg',
  });
});

Deno.test('only running and coming promotions count', () => {
  assertEquals(toRawOffer({ ...product, promotion_status: 'upcoming' })?.externalId, 'ah-123-2026-11-17');
  assertEquals(toRawOffer({ ...product, promotion_status: 'historical' }), null);
  assertEquals(toRawOffer({ ...product, promotion_status: 'shelf' }), null);
  assertEquals(toRawOffer({ ...product, is_promotional: false }), null);
  assertEquals(toRawOffer({ ...product, valid_until: null }), null);
});

Deno.test('a date with a time keeps only the day', () => {
  assertEquals(toRawOffer({ ...product, valid_until: '2026-11-23T23:59:00+01:00' })?.validTo, '2026-11-23');
});

Deno.test('at Aldi a bundle price is split over the items in it', () => {
  // Aldi publishes "2 VOOR 0.79" as price 0.79 for two items; elsewhere price is one item.
  const aldi = {
    ...product,
    retailer: 'aldi',
    price: 0.79,
    multi_buy_quantity: 2,
    multi_buy_price: 0.79,
    promotional_keywords: [],
  };
  assertEquals(toRawOffer(aldi)?.priceCents, 40);
  assertEquals(toRawOffer({ ...aldi, retailer: 'jumbo' })?.priceCents, 79);
});

Deno.test('a bundle without its own label gets one', () => {
  const bundle = {
    ...product,
    promotion_type: 'multi_buy',
    multi_buy_quantity: 2,
    multi_buy_price: 3,
    promotional_keywords: [],
  };
  assertEquals(toRawOffer(bundle)?.promoLabel, '2 voor 3,00');
});

Deno.test('pack sizes are read in grams, millilitres or pieces', () => {
  assertEquals(parseQuantity('500 g'), { quantityValue: 500, quantityUnit: 'g' });
  assertEquals(parseQuantity('1,5 kg'), { quantityValue: 1500, quantityUnit: 'g' });
  assertEquals(parseQuantity('750 ml'), { quantityValue: 750, quantityUnit: 'ml' });
  assertEquals(parseQuantity('33 cl'), { quantityValue: 330, quantityUnit: 'ml' });
  assertEquals(parseQuantity('1,5 liter'), { quantityValue: 1500, quantityUnit: 'ml' });
  assertEquals(parseQuantity('2 x 250 gram'), { quantityValue: 500, quantityUnit: 'g' });
  assertEquals(parseQuantity('6 stuks'), { quantityValue: 6, quantityUnit: 'piece' });
  assertEquals(parseQuantity('per bos'), undefined);
  assertEquals(parseQuantity(null), undefined);
});

type Call = { url: string; headers: Headers };

function fakeFetch(pages: PrijsProfeetProduct[][], total: number, calls: Call[], status: number[] = []) {
  return (url: string, init: RequestInit) => {
    calls.push({ url, headers: new Headers(init.headers) });
    const code = status.shift() ?? 200;
    if (code !== 200) return Promise.resolve(new Response('busy', { status: code, headers: { 'Retry-After': '1' } }));
    const page = Number(new URL(url).searchParams.get('page'));
    return Promise.resolve(Response.json({ total, page, page_size: 100, products: pages[page - 1] ?? [] }));
  };
}

Deno.test('every page of one chain is fetched, politely and in turn', async () => {
  const calls: Call[] = [];
  const waits: number[] = [];
  const provider = new PrijsProfeetProvider('jumbo', 'Jumbo', {
    fetch: fakeFetch([[product], [{ ...product, product_id: 'b' }]], 150, calls),
    sleep: (ms) => {
      waits.push(ms);
      return Promise.resolve();
    },
    userAgent: 'Fitling/1.0',
  });
  const { offers, more } = await provider.fetchOffers(1);
  assertEquals(offers.map((o) => o.externalId), ['ah-123-2026-11-17', 'b']);
  assertEquals(more, false);
  assertEquals(calls.length, 2);
  const first = new URL(calls[0].url);
  assertEquals(first.origin + first.pathname, 'https://www.prijsprofeet.nl/api/v1/products');
  assertEquals(first.searchParams.get('retailer'), 'jumbo');
  assertEquals(first.searchParams.get('is_promotional'), 'true');
  assertEquals(first.searchParams.get('page_size'), '100');
  assertEquals(calls[0].headers.get('User-Agent'), 'Fitling/1.0');
  assertEquals(calls[0].headers.get('X-API-Key'), null);
  // Without a key the bulk endpoints allow 30 requests a minute.
  assertEquals(waits, [2100]);
});

Deno.test('with a key the key is sent and the wait is shorter', async () => {
  const calls: Call[] = [];
  const waits: number[] = [];
  const provider = new PrijsProfeetProvider('plus', 'PLUS', {
    fetch: fakeFetch([[product], [product]], 200, calls),
    sleep: (ms) => {
      waits.push(ms);
      return Promise.resolve();
    },
    userAgent: 'Fitling/1.0',
    apiKey: 'pp_key',
  });
  await provider.fetchOffers(1);
  assertEquals(calls[0].headers.get('X-API-Key'), 'pp_key');
  assertEquals(waits, [450]);
});

Deno.test('a busy answer is waited out and tried again', async () => {
  const calls: Call[] = [];
  const waits: number[] = [];
  const provider = new PrijsProfeetProvider('dirk', 'Dirk', {
    fetch: fakeFetch([[product]], 1, calls, [429]),
    sleep: (ms) => {
      waits.push(ms);
      return Promise.resolve();
    },
    userAgent: 'Fitling/1.0',
  });
  assertEquals((await provider.fetchOffers(1)).offers.length, 1);
  assertEquals(waits, [1000]);
});

Deno.test('an error that does not pass makes the chain fail', async () => {
  const provider = new PrijsProfeetProvider('dirk', 'Dirk', {
    fetch: fakeFetch([], 0, [], [500]),
    sleep: () => Promise.resolve(),
    userAgent: 'Fitling/1.0',
  });
  await assertRejects(() => provider.fetchOffers(1), Error, 'prijsprofeet dirk: 500');
});

const pageOf = (call: Call) => Number(new URL(call.url).searchParams.get('page'));

Deno.test('a large chain comes in parts of 20 pages, so one call stays within the CPU limit', async () => {
  const calls: Call[] = [];
  const waits: number[] = [];
  const pages = Array.from({ length: 45 }, (_, i) => [{ ...product, product_id: `p${i + 1}` }]);
  const provider = new PrijsProfeetProvider('albert_heijn', 'Albert Heijn', {
    fetch: fakeFetch(pages, 4500, calls),
    sleep: (ms) => {
      waits.push(ms);
      return Promise.resolve();
    },
    userAgent: 'Fitling/1.0',
  });

  const second = await provider.fetchOffers(2);
  assertEquals(calls.map(pageOf), Array.from({ length: 20 }, (_, i) => 21 + i));
  assertEquals(second.offers.length, 20);
  assertEquals(second.more, true);
  // No wait before the first page of a call: the calls themselves are minutes apart.
  assertEquals(waits.length, 19);

  calls.length = 0;
  const third = await provider.fetchOffers(3);
  assertEquals(calls.map(pageOf), [41, 42, 43, 44, 45]);
  assertEquals(third.more, false);

  calls.length = 0;
  const fourth = await provider.fetchOffers(4);
  assertEquals(calls.map(pageOf), [61]);
  assertEquals(fourth, { offers: [], more: false });
});

Deno.test('a chain of exactly one part has nothing more', async () => {
  const calls: Call[] = [];
  const pages = Array.from({ length: 20 }, (_, i) => [{ ...product, product_id: `p${i + 1}` }]);
  const provider = new PrijsProfeetProvider('jumbo', 'Jumbo', {
    fetch: fakeFetch(pages, 2000, calls),
    sleep: () => Promise.resolve(),
    userAgent: 'Fitling/1.0',
  });
  assertEquals((await provider.fetchOffers(1)).more, false);
  assertEquals(calls.length, 20);
});

Deno.test('one provider per Dutch chain, under an id the supermarkets table accepts', () => {
  const providers = prijsProfeetProviders({ fetch, sleep: () => Promise.resolve(), userAgent: 'Fitling/1.0' });
  assertEquals(providers.length, Object.keys(chains).length);
  assertEquals(providers.length, 20);
  for (const provider of providers) {
    assertEquals(/^[a-z0-9_]{2,30}$/.test(provider.supermarketId), true, provider.supermarketId);
  }
});
