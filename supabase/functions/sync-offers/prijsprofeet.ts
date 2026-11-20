import type { OfferProvider, RawOffer } from './provider.ts';

/**
 * Offers from PrijsProfeet (prijsprofeet.nl), chosen as the source on 2026-11-20 (RISKS R-13). Their API
 * terms allow commercial use, also on the free plan, with a visible credit and a link to prijsprofeet.nl
 * on every screen that shows the data; the app does that under the offers. A key, when set, raises the
 * limit and never leaves the server. https://www.prijsprofeet.nl/api-voorwaarden
 */
export const prijsProfeetBase = 'https://www.prijsprofeet.nl/api/v1';

/** The Dutch chains, by PrijsProfeet's retailer key, which is also our supermarkets.id. */
export const chains: Record<string, string> = {
  albert_heijn: 'Albert Heijn',
  jumbo: 'Jumbo',
  lidl: 'Lidl',
  aldi: 'Aldi',
  plus: 'PLUS',
  dirk: 'Dirk',
  vomar: 'Vomar',
  hoogvliet: 'Hoogvliet',
  dekamarkt: 'DekaMarkt',
  poiesz: 'Poiesz',
  coop: 'Coop',
  gewoon_coop: 'Gewoon Coop',
  spar: 'SPAR',
  ekoplaza: 'Ekoplaza',
  nettorama: 'Nettorama',
  boni: 'Boni',
  mcd: 'MCD',
  boons_markt: "Boon's Markt",
  dagwinkel: 'Dagwinkel',
  amazing_oriental: 'Amazing Oriental',
};

/** The fields of PrijsProfeet's ProductResponse that an offer needs (openapi.json). */
export type PrijsProfeetProduct = {
  product_id: string;
  name: string;
  brand?: string | null;
  ean?: string | null;
  image_url?: string | null;
  price: number;
  original_price?: number | null;
  multi_buy_quantity?: number | null;
  multi_buy_price?: number | null;
  quantity?: string | null;
  retailer: string;
  is_promotional: boolean;
  promotion_type?: string | null;
  promotion_status?: string | null;
  promotional_keywords?: string[];
  valid_from?: string | null;
  valid_until?: string | null;
};

export type Options = {
  fetch: (url: string, init: RequestInit) => Promise<Response>;
  sleep: (ms: number) => Promise<void>;
  userAgent: string;
  apiKey?: string;
};

/** Without a key the bulk endpoints allow 30 requests a minute, with a free key 150 (their README, "Limieten"). */
const waitWithoutKey = 2100;
const waitWithKey = 450;
const pageSize = 100;
/**
 * Pages per call. Albert Heijn's 56 pages in one call used 2.08 s of CPU on Supabase, past the 2 s limit
 * (2026-11-20); 20 pages stays well within it.
 */
const pagesPerPart = 20;
const maxRetries = 2;

const units: Record<string, ['g' | 'ml' | 'piece', number]> = {
  g: ['g', 1],
  gr: ['g', 1],
  gram: ['g', 1],
  kg: ['g', 1000],
  kilo: ['g', 1000],
  ml: ['ml', 1],
  cl: ['ml', 10],
  l: ['ml', 1000],
  liter: ['ml', 1000],
  st: ['piece', 1],
  stuk: ['piece', 1],
  stuks: ['piece', 1],
};

/** "500 g", "1,5 kg", "33 cl", "2 x 250 gram", "6 stuks"; undefined when it names no amount we can compare. */
export function parseQuantity(
  text?: string | null,
): { quantityValue: number; quantityUnit: 'g' | 'ml' | 'piece' } | undefined {
  if (!text) return undefined;
  const clean = text.toLowerCase().replace(/,/g, '.');
  const unit = '(kg|kilo|gram|gr|g|liter|ml|cl|l|stuks|stuk|st)\\b';
  const multi = clean.match(new RegExp(`(\\d+(?:\\.\\d+)?)\\s*x\\s*(\\d+(?:\\.\\d+)?)\\s*${unit}`));
  const single = clean.match(new RegExp(`(\\d+(?:\\.\\d+)?)\\s*${unit}`));
  const [count, amount, name] = multi
    ? [Number(multi[1]), Number(multi[2]), multi[3]]
    : single
    ? [1, Number(single[1]), single[2]]
    : [0, 0, ''];
  const found = units[name];
  if (!found || !(count * amount > 0)) return undefined;
  return { quantityValue: Math.round(count * amount * found[1] * 100) / 100, quantityUnit: found[0] };
}

function euro(value: number): string {
  return value.toFixed(2).replace('.', ',');
}

/** One running or coming promotion as an offer; null for anything else (a shelf price, an old price). */
export function toRawOffer(product: PrijsProfeetProduct): RawOffer | null {
  if (!product.is_promotional) return null;
  if (product.promotion_status && !['active', 'upcoming'].includes(product.promotion_status)) return null;
  const validFrom = product.valid_from?.slice(0, 10);
  const validTo = product.valid_until?.slice(0, 10);
  if (!validFrom || !validTo) return null;
  // Aldi publishes a bundle total as its price ("2 VOOR 0.79"); every other chain the price of one item.
  const bundle = product.multi_buy_quantity ?? 0;
  const price = product.retailer.startsWith('aldi') && bundle > 1 ? product.price / bundle : product.price;
  const label = product.promotional_keywords?.find((word) => word.trim() !== '') ??
    (product.promotion_type === 'multi_buy' && bundle > 1 && product.multi_buy_price
      ? `${bundle} voor ${euro(product.multi_buy_price)}`
      : undefined);
  const offer: RawOffer = {
    externalId: product.product_id,
    title: product.name,
    priceCents: Math.round(price * 100),
    validFrom,
    validTo,
  };
  if (product.brand) offer.brand = product.brand;
  if (product.ean) offer.gtin = product.ean;
  const quantity = parseQuantity(product.quantity);
  if (quantity) Object.assign(offer, quantity);
  if (product.original_price) offer.regularPriceCents = Math.round(product.original_price * 100);
  if (label) offer.promoLabel = label;
  if (product.image_url) offer.imageUrl = product.image_url;
  return offer;
}

/** The running and coming promotions of one chain, 20 pages per part, within PrijsProfeet's limits. */
export class PrijsProfeetProvider implements OfferProvider {
  constructor(readonly supermarketId: string, readonly supermarketName: string, private readonly options: Options) {}

  async fetchOffers(part: number): Promise<{ offers: RawOffer[]; more: boolean }> {
    const offers: RawOffer[] = [];
    const first = (part - 1) * pagesPerPart + 1;
    const last = part * pagesPerPart;
    for (let page = first; page <= last; page++) {
      if (page > first) await this.options.sleep(this.options.apiKey ? waitWithKey : waitWithoutKey);
      const { products, total } = await this.page(page);
      for (const product of products) {
        const offer = toRawOffer(product);
        if (offer) offers.push(offer);
      }
      if (products.length === 0 || page * pageSize >= total) return { offers, more: false };
    }
    return { offers, more: true };
  }

  private async page(page: number): Promise<{ products: PrijsProfeetProduct[]; total: number }> {
    const url = new URL(`${prijsProfeetBase}/products`);
    url.searchParams.set('retailer', this.supermarketId);
    url.searchParams.set('is_promotional', 'true');
    url.searchParams.set('page', String(page));
    url.searchParams.set('page_size', String(pageSize));
    const headers: Record<string, string> = { 'User-Agent': this.options.userAgent, Accept: 'application/json' };
    if (this.options.apiKey) headers['X-API-Key'] = this.options.apiKey;
    for (let attempt = 0;; attempt++) {
      const response = await this.options.fetch(url.toString(), { headers });
      if (response.ok) {
        const body = await response.json();
        return { products: Array.isArray(body.products) ? body.products : [], total: Number(body.total) || 0 };
      }
      await response.body?.cancel();
      if ((response.status === 429 || response.status === 503) && attempt < maxRetries) {
        await this.options.sleep((Number(response.headers.get('Retry-After')) || 60) * 1000);
        continue;
      }
      throw new Error(`prijsprofeet ${this.supermarketId}: ${response.status}`);
    }
  }
}

export function prijsProfeetProviders(options: Options): OfferProvider[] {
  return Object.entries(chains).map(([id, name]) => new PrijsProfeetProvider(id, name, options));
}
