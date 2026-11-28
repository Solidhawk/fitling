import type { SupabaseClient } from "@supabase/supabase-js";
import type { FitlingCore, OwnProductFields } from "../core/fitlingCore";
import { failure } from "./failure";
import { noNetwork } from "./offline";

/** A product as the app keeps it (Product on iOS): shared (`ownerID` nil) or the user's own. */
export interface Product {
  id: string;
  ownerID: string | null;
  source: string;
  gtin?: string;
  name: Record<string, string>;
  brand?: string;
  searchName: string;
  quantityUnit: "g" | "ml";
  servingSize?: number;
  servingLabel?: string;
  kcal100?: number;
  protein100?: number;
  carbs100?: number;
  sugars100?: number;
  fat100?: number;
  saturatedFat100?: number;
  fiber100?: number;
  salt100?: number;
  imageURL?: string;
  fetchedAt?: string;
  /** Checked by us or from NEVO: ranks before an unchecked match in a search. */
  isVerified?: boolean;
}

type Row = Record<string, unknown>;

function optional<T>(value: unknown): T | undefined {
  return value === null || value === undefined ? undefined : (value as T);
}

function number(value: unknown): number | undefined {
  return value === null || value === undefined ? undefined : Number(value);
}

export function productFromRow(row: Row): Product {
  return {
    id: row.id as string,
    ownerID: (row.owner_id as string | null) ?? null,
    source: row.source as string,
    gtin: optional(row.gtin),
    name: (row.name as Record<string, string>) ?? {},
    brand: optional(row.brand),
    searchName: (row.search_name as string) ?? "",
    quantityUnit: row.quantity_unit === "ml" ? "ml" : "g",
    servingSize: number(row.serving_size),
    servingLabel: optional(row.serving_label),
    kcal100: number(row.kcal_100),
    protein100: number(row.protein_100),
    carbs100: number(row.carbs_100),
    sugars100: number(row.sugars_100),
    fat100: number(row.fat_100),
    saturatedFat100: number(row.saturated_fat_100),
    fiber100: number(row.fiber_100),
    salt100: number(row.salt_100),
    imageURL: optional(row.image_url),
    fetchedAt: optional(row.fetched_at),
    isVerified: row.is_verified === true,
  };
}

/** Ids per request: hundreds of them in one query string would be more than the server takes. */
const idsPerRequest = 50;

/** The products with these ids, in the same order, without deleted ones. */
export async function productsByID(client: SupabaseClient, ids: string[]): Promise<Product[]> {
  const batches = Array.from({ length: Math.ceil(ids.length / idsPerRequest) }, (_, index) =>
    ids.slice(index * idsPerRequest, (index + 1) * idsPerRequest),
  );
  const answers = await Promise.all(batches.map((batch) => client.from("products").select("*").in("id", batch).is("deleted_at", null)));
  const byID = new Map<string, Product>();
  for (const { data, error } of answers) {
    if (error) throw failure(error);
    for (const row of data as Row[]) byID.set(row.id as string, productFromRow(row));
  }
  return ids.flatMap((id) => byID.get(id) ?? []);
}

/** Online results appear from this many characters on, so a single letter does not ask the server for everything. */
export const onlineSearchMinimum = 3;
export const searchLimit = 30;

/** The products that hold every word of `key`, each once, best first (FoodLog.bestMatches, as on the iPhone). */
function bestMatches(core: FitlingCore, key: string, products: Product[]): Product[] {
  const byID = new Map<string, Product>();
  for (const product of products) if (!byID.has(product.id)) byID.set(product.id, product);
  const candidates = [...byID.values()].map((product) => ({ id: product.id, searchName: product.searchName, isVerified: product.isVerified ?? false }));
  return core.searchMatches({ key, products: candidates }).ids.flatMap((id) => byID.get(id) ?? []);
}

/**
 * Searching by name, as LogFoodViewModel.runSearch: first the user's own products and those they logged or marked
 * before (on an iPhone: "on this device"), then shared products from three characters on, without doubles.
 */
export async function searchProducts(
  client: SupabaseClient,
  core: FitlingCore,
  query: string,
  known: Product[],
): Promise<{ own: Product[]; online: Product[]; failed?: string }> {
  const { key: term } = core.searchKey({ text: query });
  if (term === "") return { own: [], online: [] };
  const knownMatches = bestMatches(core, term, known);
  // Without a network: what this browser knows, as the iPhone searches its own copy.
  if (noNetwork()) return { own: knownMatches.slice(0, searchLimit), online: [] };
  // Every word anywhere in the name, each taken literally with `imatch` (FoodLog.searchPattern); bestMatches ranks.
  let mineQuery = client.from("products").select("*").not("owner_id", "is", null).is("deleted_at", null);
  for (const word of term.split(" ").filter(Boolean)) mineQuery = mineQuery.filter("search_name", "imatch", core.searchKey({ text: word }).pattern);
  const mine = await mineQuery.limit(searchLimit);
  // A read that fails keeps what was found so far, with the reason to tell (UNFORGET S58): the iPhone keeps its
  // own results too when the online search fails.
  if (mine.error) return { own: knownMatches.slice(0, searchLimit), online: [], failed: failure(mine.error).message };
  const own = bestMatches(core, term, [...(mine.data as Row[]).map(productFromRow), ...knownMatches]).slice(0, searchLimit);
  if (term.length < onlineSearchMinimum) return { own, online: [] };
  // The server ranks the shared products the same way (supabase/search-products.sql).
  const shared = await client.rpc("search_products", { search_key: term, max_results: searchLimit });
  if (shared.error) return { own, online: [], failed: failure(shared.error).message };
  const shown = new Set(own.map((product) => product.id));
  return { own, online: (shared.data as Row[]).map(productFromRow).filter((product) => !shown.has(product.id)) };
}

/** The name in the user's languages, with the fallbacks of LocalizedText. */
export function productName(core: FitlingCore, product: Product, languages: readonly string[] = navigator.languages): string {
  return core.localizedText({ values: product.name, languages: [...languages] }).text;
}

function ownRow(userID: string, fields: OwnProductFields, name: Record<string, string>, now: Date) {
  return {
    id: crypto.randomUUID(),
    owner_id: userID,
    source: "user",
    name,
    brand: fields.brand ?? null,
    gtin: fields.gtin ?? null,
    search_name: fields.searchName,
    quantity_unit: fields.quantityUnit,
    serving_size: fields.servingSize ?? null,
    kcal_100: fields.kcal100,
    protein_100: fields.protein100 ?? null,
    carbs_100: fields.carbs100 ?? null,
    fat_100: fields.fat100 ?? null,
    updated_at: now.toISOString(),
  };
}

/** A product typed in from the package (AddProductViewModel.save), stored under the user's own language. */
export async function addOwnProduct(client: SupabaseClient, userID: string, fields: OwnProductFields, language: string, now: Date): Promise<Product> {
  const row = ownRow(userID, fields, { [language]: fields.name }, now);
  const { error } = await client.from("products").insert(row);
  if (error) throw failure(error);
  return productFromRow(row);
}

/** The row of the user's own copy of a product: every value of the package, with the kcal the user read on it. */
export function ownCopyRow(userID: string, product: Product, kcal100: number, now: Date) {
  return {
    id: crypto.randomUUID(),
    owner_id: userID,
    source: "user",
    name: product.name,
    brand: product.brand ?? null,
    gtin: product.gtin ?? null,
    search_name: product.searchName,
    quantity_unit: product.quantityUnit,
    serving_size: product.servingSize ?? null,
    serving_label: product.servingLabel ?? null,
    kcal_100: kcal100,
    protein_100: product.protein100 ?? null,
    carbs_100: product.carbs100 ?? null,
    sugars_100: product.sugars100 ?? null,
    fat_100: product.fat100 ?? null,
    saturated_fat_100: product.saturatedFat100 ?? null,
    fiber_100: product.fiber100 ?? null,
    salt_100: product.salt100 ?? null,
    image_url: product.imageURL ?? null,
    updated_at: now.toISOString(),
  };
}

/**
 * For a product the source gave no kcal for: the user's own copy with the kcal they read on the package. The shared
 * row stays as it is (FoodDiary.ownCopy, ARCHITECTURE section 5.2).
 */
export async function ownCopy(client: SupabaseClient, userID: string, product: Product, kcal100: number, now: Date): Promise<Product> {
  const row = ownCopyRow(userID, product, kcal100, now);
  const { error } = await client.from("products").insert(row);
  if (error) throw failure(error);
  return productFromRow(row);
}

/** A corrected kcal on the user's own copy, when logging it failed the first time and the user changed the number. */
export async function setOwnKcal(client: SupabaseClient, product: Product, kcal100: number, now: Date): Promise<Product> {
  const { error } = await client.from("products").update({ kcal_100: kcal100, updated_at: now.toISOString() }).eq("id", product.id);
  if (error) throw failure(error);
  return { ...product, kcal100 };
}
