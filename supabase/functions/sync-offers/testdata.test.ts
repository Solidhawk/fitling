import { assert, assertEquals } from '@std/assert';
import { offerRow } from './normalize.ts';
import { TestDataProvider } from './testdata.ts';

Deno.test('the test offers run from Monday to Sunday of the current week', async () => {
  const offers = await new TestDataProvider(() => new Date('2026-11-19T04:00:00Z')).fetchOffers();
  assert(offers.length >= 8);
  for (const offer of offers) {
    assertEquals([offer.validFrom, offer.validTo], ['2026-11-16', '2026-11-22']);
  }
});

Deno.test('on a Sunday the week still started on Monday', async () => {
  const [first] = await new TestDataProvider(() => new Date('2026-11-22T23:00:00Z')).fetchOffers();
  assertEquals([first.validFrom, first.validTo], ['2026-11-16', '2026-11-22']);
});

Deno.test('every test offer passes the checks of the table', async () => {
  const offers = await new TestDataProvider(() => new Date('2026-11-19T04:00:00Z')).fetchOffers();
  for (const offer of offers) {
    assert(offerRow(offer, 'testwinkel', new Date()) !== null, offer.externalId);
  }
  assertEquals(new Set(offers.map((o) => o.externalId)).size, offers.length);
});
