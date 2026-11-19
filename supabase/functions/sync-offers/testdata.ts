import type { OfferProvider, RawOffer } from './provider.ts';

/**
 * The only source until it is settled which sources may be used (RISKS R-13). A shop that does not
 * exist, with plain products that recipes use, valid from Monday to Sunday of the current week.
 */
export class TestDataProvider implements OfferProvider {
  readonly supermarketId = 'testwinkel';
  readonly supermarketName = 'Testwinkel';

  constructor(private readonly now: () => Date) {}

  fetchOffers(): Promise<RawOffer[]> {
    const today = this.now();
    const sinceMonday = (today.getUTCDay() + 6) % 7;
    const monday = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate() - sinceMonday));
    const sunday = new Date(monday.getTime() + 6 * 86_400_000);
    const day = (date: Date) => date.toISOString().slice(0, 10);
    const week = { validFrom: day(monday), validTo: day(sunday) };
    const offers: RawOffer[] = [
      {
        externalId: 'melk',
        title: 'Halfvolle melk',
        quantityValue: 1000,
        quantityUnit: 'ml',
        priceCents: 99,
        regularPriceCents: 125,
      },
      {
        externalId: 'kipfilet',
        title: 'Kipfilet',
        quantityValue: 500,
        quantityUnit: 'g',
        priceCents: 549,
        regularPriceCents: 699,
      },
      {
        externalId: 'tomaten',
        title: 'Trostomaten',
        quantityValue: 500,
        quantityUnit: 'g',
        priceCents: 149,
        regularPriceCents: 219,
      },
      {
        externalId: 'yoghurt',
        title: 'Magere yoghurt',
        quantityValue: 1000,
        quantityUnit: 'ml',
        priceCents: 109,
        promoLabel: '2e halve prijs',
      },
      { externalId: 'bananen', title: 'Bananen', quantityValue: 1000, quantityUnit: 'g', priceCents: 169 },
      {
        externalId: 'pasta',
        title: 'Volkoren penne',
        quantityValue: 500,
        quantityUnit: 'g',
        priceCents: 119,
        regularPriceCents: 159,
      },
      {
        externalId: 'eieren',
        title: 'Scharreleieren',
        quantityValue: 10,
        quantityUnit: 'piece',
        priceCents: 259,
        regularPriceCents: 319,
      },
      {
        externalId: 'havermout',
        title: 'Havermout',
        quantityValue: 500,
        quantityUnit: 'g',
        priceCents: 89,
        promoLabel: '1+1 gratis',
      },
      {
        externalId: 'broccoli',
        title: 'Broccoli',
        quantityValue: 500,
        quantityUnit: 'g',
        priceCents: 129,
        regularPriceCents: 179,
      },
      {
        externalId: 'kwark',
        title: 'Magere kwark',
        quantityValue: 500,
        quantityUnit: 'g',
        priceCents: 139,
        regularPriceCents: 189,
      },
    ].map((offer) => ({ ...offer, ...week } as RawOffer));
    return Promise.resolve(offers);
  }
}
