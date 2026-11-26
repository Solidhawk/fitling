import { FunctionsHttpError, type SupabaseClient } from "@supabase/supabase-js";
import type { FitlingCore } from "../core/fitlingCore";
import { failure } from "./failure";
import { noNetwork } from "./offline";
import { type Product, productFromRow } from "./products";

/** What a scanned or typed barcode led to (ProductLookupResult and LogFoodViewModel.ScanOutcome). */
export type LookupResult =
  | { kind: "found"; product: Product }
  /** Nobody knows this barcode: offer to add it as the user's own product. */
  | { kind: "notFound"; gtin: string }
  /** The server could not be asked and there is no copy: keep the barcode, try again later. */
  | { kind: "unavailable"; gtin: string }
  /** Not a valid EAN-8, EAN-13 or UPC-A: a misread, the scanner keeps looking. */
  | { kind: "invalid" };

/** A shared product is asked again after this long; the user's own products never expire (ProductLookup.freshFor). */
export const freshForMs = 30 * 24 * 60 * 60 * 1000;

function isFresh(product: Product, now: Date): boolean {
  if (product.ownerID !== null) return true;
  return product.fetchedAt !== undefined && now.getTime() - Date.parse(product.fetchedAt) < freshForMs;
}

/**
 * Finds the product behind a barcode: a copy the user can already read first (their own before a shared one), then
 * the Edge Function lookup-product (ARCHITECTURE §5, steps 1 and 2). Offline an old copy is better than nothing.
 */
export async function lookUp(client: SupabaseClient, core: FitlingCore, scanned: string, now: Date): Promise<LookupResult> {
  const { gtin } = core.barcode({ text: scanned });
  if (!gtin) return { kind: "invalid" };
  if (noNetwork()) return { kind: "unavailable", gtin };

  let local: Product | undefined;
  const stored = await client.from("products").select("*").eq("gtin", gtin).is("deleted_at", null);
  if (!stored.error) {
    const products = (stored.data as Record<string, unknown>[]).map(productFromRow);
    local = products.find((product) => product.ownerID !== null) ?? products[0];
    if (local && isFresh(local, now)) return { kind: "found", product: local };
  } else if (failure(stored.error).message === "error.server") {
    throw failure(stored.error);
  }

  const { data, error } = await client.functions.invoke("lookup-product", { body: { gtin } });
  if (!error) return { kind: "found", product: productFromRow(data as Record<string, unknown>) };
  if (error instanceof FunctionsHttpError && (error.context as Response).status === 404) {
    return local ? { kind: "found", product: local } : { kind: "notFound", gtin };
  }
  return local ? { kind: "found", product: local } : { kind: "unavailable", gtin };
}
