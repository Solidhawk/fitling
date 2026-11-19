/** One source of offers for one supermarket (ARCHITECTURE §6). Adding or replacing a source is one file. */
export interface OfferProvider {
  /** Equal to supermarkets.id. */
  readonly supermarketId: string;
  /** Shown in the app; written to supermarkets.name. */
  readonly supermarketName: string;
  /** All offers that apply now or soon. */
  fetchOffers(): Promise<RawOffer[]>;
}

export interface RawOffer {
  externalId: string;
  title: string;
  brand?: string;
  gtin?: string;
  quantityValue?: number;
  quantityUnit?: 'g' | 'ml' | 'piece';
  priceCents: number;
  regularPriceCents?: number;
  promoLabel?: string;
  /** "2026-11-18" */
  validFrom: string;
  validTo: string;
  imageUrl?: string;
}
