import { readFile } from "node:fs/promises";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, test } from "vitest";
import { type FitlingCore, loadCore } from "../core/fitlingCore";
import {
  addWater,
  deleteEntry,
  entriesOn,
  favoriteProducts,
  isFavorite,
  logProduct,
  recentProducts,
  setFavorite,
  waterOn,
} from "./diary";
import { type Product, productFromRow, searchProducts } from "./products";

// Against the local Supabase that CI starts (never the real project); FoodLogTests on iOS.
const url = process.env.VITE_SUPABASE_URL;
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const serviceKey = process.env.LOCAL_SUPABASE_SERVICE_KEY;
const day = "2026-11-24";

describe.skipIf(!url || !key || !serviceKey)("the food diary on the server", () => {
  let core: FitlingCore;
  let admin: SupabaseClient;

  beforeAll(async () => {
    const file = await readFile(new URL("../../public/fitling-core.wasm", import.meta.url));
    core = await loadCore(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer);
    admin = createClient(url!, serviceKey!, { auth: { persistSession: false } });
  });

  async function user() {
    const email = `diary-${crypto.randomUUID()}@fitling.test`;
    const password = "lang-genoeg-wachtwoord-1";
    const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (created.error) throw created.error;
    const client = createClient(url!, key!, { auth: { persistSession: false } });
    const signIn = await client.auth.signInWithPassword({ email, password });
    if (signIn.error) throw signIn.error;
    return { id: created.data.user.id, client };
  }

  /** A shared product, as the Edge Function stores it; users cannot write those themselves. */
  async function shared(name: string, values: Partial<Record<string, unknown>> = {}): Promise<Product> {
    const row = {
      id: crypto.randomUUID(),
      source: "off",
      name: { nl: name },
      search_name: core.searchKey({ text: name }).key,
      quantity_unit: "g",
      kcal_100: 250,
      protein_100: 10,
      carbs_100: 30,
      fat_100: 8,
      updated_at: new Date().toISOString(),
      ...values,
    };
    const { error } = await admin.from("products").insert(row);
    if (error) throw error;
    return productFromRow(row);
  }

  test("loggingStoresASnapshotOfNameAndValues", async () => {
    const { id, client } = await user();
    const product = await shared(`Volkorenbrood ${crypto.randomUUID()}`);
    const entry = await logProduct(client, core, { userID: id, product, quantity: 35.04, unit: "g", meal: "breakfast", day, now: new Date() });
    expect(entry).toMatchObject({ name: product.name.nl, quantity: 35, kcal: 87.6, proteinG: 3.5, meal: "breakfast" });
    await admin.from("products").update({ kcal_100: 999 }).eq("id", product.id);
    expect((await entriesOn(client, day))[0].kcal).toBe(87.6);
  });

  test("servingsUseTheServingSize", async () => {
    const { id, client } = await user();
    const product = await shared(`Muesli ${crypto.randomUUID()}`, { serving_size: 45 });
    const entry = await logProduct(client, core, { userID: id, product, quantity: 2, unit: "serving", meal: "breakfast", day, now: new Date() });
    expect(entry.kcal).toBe(225);
  });

  test("unknownMacrosAreStoredAsUnknown", async () => {
    const { id, client } = await user();
    const product = await shared(`Thee ${crypto.randomUUID()}`, { protein_100: null, carbs_100: null, fat_100: null, kcal_100: 1 });
    await logProduct(client, core, { userID: id, product, quantity: 250, unit: "g", meal: "snack", day, now: new Date() });
    const [entry] = await entriesOn(client, day);
    expect(entry.proteinG).toBeUndefined();
    expect(entry.fatG).toBeUndefined();
  });

  test("recentShowsEachProductOnce", async () => {
    const { id, client } = await user();
    const bread = await shared(`Brood ${crypto.randomUUID()}`);
    const cheese = await shared(`Kaas ${crypto.randomUUID()}`);
    for (const [product, minutes] of [[bread, 1], [cheese, 2], [bread, 3]] as const) {
      await logProduct(client, core, { userID: id, product, quantity: 50, unit: "g", meal: "lunch", day, now: new Date(Date.UTC(2026, 10, 24, 12, minutes)) });
    }
    expect((await recentProducts(client, core)).map((product) => product.id)).toEqual([bread.id, cheese.id]);
  });

  test("favoritesCanBeSetAndCleared", async () => {
    const { id, client } = await user();
    const product = await shared(`Yoghurt ${crypto.randomUUID()}`);
    await setFavorite(client, id, product.id, true, new Date());
    await setFavorite(client, id, product.id, true, new Date());
    expect((await favoriteProducts(client)).map((favorite) => favorite.id)).toEqual([product.id]);
    await setFavorite(client, id, product.id, false, new Date());
    expect(await isFavorite(client, product.id)).toBe(false);
  });

  test("searchFindsOwnProductsFirstAndAddsOnlineOnes", async () => {
    const { client } = await user();
    const word = `zoekwoord${crypto.randomUUID().slice(0, 8)}`;
    const online = await shared(`${word} gedeeld`);
    const known = productFromRow({ id: crypto.randomUUID(), owner_id: null, source: "off", name: { nl: `${word} eerder` }, search_name: `${word} eerder` });
    const found = await searchProducts(client, core, word, [known]);
    expect(found.own.map((product) => product.id)).toEqual([known.id]);
    expect(found.online.map((product) => product.id)).toEqual([online.id]);
  });

  test("aShortQueryStaysLocal", async () => {
    const { client } = await user();
    await shared("ab gedeeld kort");
    expect((await searchProducts(client, core, "ab", [])).online).toEqual([]);
  });

  test("aSearchTermIsTakenLiterally", async () => {
    const { client } = await user();
    const word = crypto.randomUUID().slice(0, 8);
    const odd = await shared(`Mix ${word} (a+b) [50%] *x*. ^$|?{2} \\_`);
    // In a LIKE pattern PostgREST reads "*" as "%": three of them would find every product.
    for (const wildcard of ["%%%", "***", "...", ".*."]) {
      expect((await searchProducts(client, core, wildcard, [])).online).toEqual([]);
    }
    const found = await searchProducts(client, core, `${word} (a+b) [50%] *x*. ^$|?{2} \\_`, []);
    expect(found.online.map((product) => product.id)).toEqual([odd.id]);
  });

  test("waterFromTwoDevicesAddsUp", async () => {
    const { id, client } = await user();
    await Promise.all([addWater(client, id, day, new Date()), addWater(client, id, day, new Date())]);
    expect(await waterOn(client, day)).toBe(500);
  });

  test("deletedEntriesDisappear", async () => {
    const { id, client } = await user();
    const product = await shared(`Appel ${crypto.randomUUID()}`);
    const entry = await logProduct(client, core, { userID: id, product, quantity: 100, unit: "g", meal: "snack", day, now: new Date() });
    await deleteEntry(client, entry.id, new Date());
    expect(await entriesOn(client, day)).toEqual([]);
  });
});
