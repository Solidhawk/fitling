import type { SupabaseClient } from "@supabase/supabase-js";
import type { FitlingCore, OwnProductFields } from "../core/fitlingCore";
import { failure } from "./failure";

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
  fat100?: number;
  imageURL?: string;
  fetchedAt?: string;
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
    fat100: number(row.fat_100),
    imageURL: optional(row.image_url),
    fetchedAt: optional(row.fetched_at),
  };
}

/** The products with these ids, in the same order, without deleted ones. */
export async function productsByID(client: SupabaseClient, ids: string[]): Promise<Product[]> {
  if (ids.length === 0) return [];
  const { data, error } = await client.from("products").select("*").in("id", ids).is("deleted_at", null);
  if (error) throw failure(error);
  const byID = new Map((data as Row[]).map((row) => [row.id as string, productFromRow(row)]));
  return ids.flatMap((id) => byID.get(id) ?? []);
}

/** A search term inside a LIKE pattern: its own wildcards are taken literally (SupabaseProductSearch). */
export function likePattern(term: string): string {
  return `%${term.replace(/\\/g, "\\\\").replace(/%/g, "\\%").replace(/_/g, "\\_")}%`;
}

/** Online results appear from this many characters on, so a single letter does not ask the server for everything. */
export const onlineSearchMinimum = 3;
export const searchLimit = 30;

/**
 * Searching by name, as LogFoodViewModel.runSearch: first the user's own products and those they logged or marked
 * before (on an iPhone: "on this device"), then shared products from three characters on, without doubles.
 */
export async function searchProducts(
  client: SupabaseClient,
  core: FitlingCore,
  query: string,
  known: Product[],
): Promise<{ own: Product[]; online: Product[] }> {
  const term = core.searchKey({ text: query }).key;
  if (term === "") return { own: [], online: [] };
  const mine = await client
    .from("products")
    .select("*")
    .not("owner_id", "is", null)
    .is("deleted_at", null)
    .ilike("search_name", likePattern(term))
    .limit(searchLimit);
  if (mine.error) throw failure(mine.error);
  const own: Product[] = [];
  for (const product of [...(mine.data as Row[]).map(productFromRow), ...known.filter((product) => product.searchName.includes(term))]) {
    if (own.length < searchLimit && !own.some((shown) => shown.id === product.id)) own.push(product);
  }
  if (term.length < onlineSearchMinimum) return { own, online: [] };
  const shared = await client
    .from("products")
    .select("*")
    .is("owner_id", null)
    .is("deleted_at", null)
    .ilike("search_name", likePattern(term))
    .limit(searchLimit);
  if (shared.error) throw failure(shared.error);
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

/**
 * For a product the source gave no kcal for: the user's own copy with the kcal they read on the package. The shared
 * row stays as it is (FoodDiary.ownCopy, ARCHITECTURE §5.2).
 */
export async function ownCopy(client: SupabaseClient, userID: string, product: Product, kcal100: number, now: Date): Promise<Product> {
  const row = {
    ...ownRow(
      userID,
      {
        name: "",
        brand: product.brand,
        gtin: product.gtin,
        quantityUnit: product.quantityUnit,
        servingSize: product.servingSize,
        kcal100,
        protein100: product.protein100,
        carbs100: product.carbs100,
        fat100: product.fat100,
        searchName: product.searchName,
      },
      product.name,
      now,
    ),
    serving_label: product.servingLabel ?? null,
    image_url: product.imageURL ?? null,
  };
  const { error } = await client.from("products").insert(row);
  if (error) throw failure(error);
  return productFromRow(row);
}
