import type { RawOffer } from './provider.ts';

/** A row for public.offers, as the job writes it. id and synced_at are left to the database. */
export type OfferRow = {
  supermarket_id: string;
  external_id: string;
  title: string;
  search_title: string;
  brand: string | null;
  gtin: string | null;
  quantity_value: number | null;
  quantity_unit: 'g' | 'ml' | 'piece' | null;
  price_cents: number;
  regular_price_cents: number | null;
  promo_label: string | null;
  valid_from: string;
  valid_to: string;
  image_url: string | null;
  fetched_at: string;
};

/**
 * The same rule as Barcode.normalized in the app: 8 or 13 digits with a valid GS1 check digit,
 * UPC-A as 13 digits with a leading zero, and null for anything else.
 */
export function normalizeBarcode(scanned: string): string | null {
  const code = scanned.replace(/\s/g, '');
  if (!/^\d+$/.test(code)) return null;
  const digits = [...code].map(Number);
  const check = digits.pop()!;
  const sum = digits.reverse().reduce((total, digit, index) => total + digit * (index % 2 === 0 ? 3 : 1), 0);
  if ((10 - (sum % 10)) % 10 !== check) return null;
  if (code.length === 8 || code.length === 13) return code;
  if (code.length === 12) return '0' + code;
  return null;
}

/** Lower case, without accents, single spaces: what OfferMatcher in the app compares against. */
export function searchTitle(title: string): string {
  return title.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase().replace(/\s+/g, ' ').trim();
}

function isDate(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
}

function text(value: string | undefined): string | null {
  const trimmed = value?.trim() ?? '';
  return trimmed === '' ? null : trimmed;
}

/** The row for one offer, or null when the table's checks would refuse it. */
export function offerRow(offer: RawOffer, supermarketId: string, fetchedAt: Date): OfferRow | null {
  const title = text(offer.title);
  const externalId = text(offer.externalId);
  const isCents = (value: number) => Number.isInteger(value) && value >= 0;
  if (title === null || externalId === null) return null;
  if (!isCents(offer.priceCents)) return null;
  if (offer.regularPriceCents !== undefined && !isCents(offer.regularPriceCents)) return null;
  if (!isDate(offer.validFrom) || !isDate(offer.validTo) || offer.validTo < offer.validFrom) return null;
  const hasQuantity = offer.quantityValue !== undefined && offer.quantityUnit !== undefined;
  if (hasQuantity && !(offer.quantityValue! > 0)) return null;
  return {
    supermarket_id: supermarketId,
    external_id: externalId,
    title,
    search_title: searchTitle(title),
    brand: text(offer.brand),
    gtin: offer.gtin === undefined ? null : normalizeBarcode(offer.gtin),
    quantity_value: hasQuantity ? offer.quantityValue! : null,
    quantity_unit: hasQuantity ? offer.quantityUnit! : null,
    price_cents: offer.priceCents,
    regular_price_cents: offer.regularPriceCents ?? null,
    promo_label: text(offer.promoLabel),
    valid_from: offer.validFrom,
    valid_to: offer.validTo,
    image_url: text(offer.imageUrl),
    fetched_at: fetchedAt.toISOString(),
  };
}
