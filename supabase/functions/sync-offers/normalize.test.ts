import { assertEquals } from '@std/assert';
import { normalizeBarcode, offerRow, searchTitle } from './normalize.ts';
import type { RawOffer } from './provider.ts';

const fetchedAt = new Date('2026-11-19T04:00:00Z');
const raw: RawOffer = {
  externalId: 'melk-1',
  title: 'Volle Melk',
  priceCents: 129,
  validFrom: '2026-11-16',
  validTo: '2026-11-22',
};

Deno.test('a barcode is stored the way the app stores it', () => {
  assertEquals(normalizeBarcode('8712100849084'), '8712100849084');
  assertEquals(normalizeBarcode('96385074'), '96385074');
  // UPC-A gets a leading zero, as in the app (Barcode.normalized).
  assertEquals(normalizeBarcode('036000291452'), '0036000291452');
  assertEquals(normalizeBarcode(' 8712100 849084 '), '8712100849084');
});

Deno.test('a barcode with a wrong check digit or length is dropped', () => {
  assertEquals(normalizeBarcode('8712100849085'), null);
  assertEquals(normalizeBarcode('12345'), null);
  assertEquals(normalizeBarcode('87121008490a4'), null);
});

Deno.test('the search title is lower case without accents and extra spaces', () => {
  assertEquals(searchTitle('  Crème  Fraîche   Naturel '), 'creme fraiche naturel');
  assertEquals(searchTitle('Jägermeister'), 'jagermeister');
});

Deno.test('a raw offer becomes a row for the offers table', () => {
  assertEquals(
    offerRow(
      { ...raw, brand: ' Melkunie ', gtin: '036000291452', quantityValue: 1000, quantityUnit: 'ml' },
      'test',
      fetchedAt,
    ),
    {
      supermarket_id: 'test',
      external_id: 'melk-1',
      title: 'Volle Melk',
      search_title: 'volle melk',
      brand: 'Melkunie',
      gtin: '0036000291452',
      quantity_value: 1000,
      quantity_unit: 'ml',
      price_cents: 129,
      regular_price_cents: null,
      promo_label: null,
      valid_from: '2026-11-16',
      valid_to: '2026-11-22',
      image_url: null,
      fetched_at: '2026-11-19T04:00:00.000Z',
    },
  );
});

Deno.test('an unreadable barcode is left out but the offer is kept', () => {
  assertEquals(offerRow({ ...raw, gtin: '123' }, 'test', fetchedAt)?.gtin, null);
});

Deno.test('an offer the table would refuse is skipped', () => {
  assertEquals(offerRow({ ...raw, title: '  ' }, 'test', fetchedAt), null);
  assertEquals(offerRow({ ...raw, externalId: '' }, 'test', fetchedAt), null);
  assertEquals(offerRow({ ...raw, priceCents: -1 }, 'test', fetchedAt), null);
  assertEquals(offerRow({ ...raw, priceCents: 1.5 }, 'test', fetchedAt), null);
  assertEquals(offerRow({ ...raw, regularPriceCents: -5 }, 'test', fetchedAt), null);
  assertEquals(offerRow({ ...raw, validFrom: '2026-11-23' }, 'test', fetchedAt), null);
  assertEquals(offerRow({ ...raw, validTo: '22-11-2026' }, 'test', fetchedAt), null);
  assertEquals(offerRow({ ...raw, quantityValue: 0, quantityUnit: 'g' }, 'test', fetchedAt), null);
});

Deno.test('a quantity without a unit is left out', () => {
  const row = offerRow({ ...raw, quantityValue: 500 }, 'test', fetchedAt);
  assertEquals([row?.quantity_value, row?.quantity_unit], [null, null]);
});
