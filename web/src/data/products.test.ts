import type { SupabaseClient } from "@supabase/supabase-js";
import { expect, test, vi } from "vitest";
import type { FitlingCore } from "../core/fitlingCore";
import { ownCopyRow, productFromRow, productsByID, searchProducts } from "./products";

// FoodDiary.ownCopy: every value of the package comes along, only the kcal are the user's.
test("anOwnCopyKeepsEveryNutrient", () => {
  const shared = productFromRow({
    id: "s1",
    owner_id: null,
    source: "off",
    name: { nl: "Thee" },
    search_name: "thee",
    quantity_unit: "ml",
    serving_size: 250,
    protein_100: 0.1,
    carbs_100: 0.2,
    sugars_100: 0.1,
    fat_100: 0,
    saturated_fat_100: 0,
    fiber_100: 0,
    salt_100: 0.01,
  });
  const row = ownCopyRow("u1", shared, 1, new Date("2026-11-24T12:00:00Z"));
  expect(row).toMatchObject({
    owner_id: "u1",
    source: "user",
    kcal_100: 1,
    sugars_100: 0.1,
    saturated_fat_100: 0,
    fiber_100: 0,
    salt_100: 0.01,
    serving_size: 250,
    quantity_unit: "ml",
  });
});

// Hundreds of ids in one query string would be more than the server takes; they go in batches.
test("manyProductsAreAskedForInBatches", async () => {
  const asked: number[] = [];
  const client = {
    from() {
      let ids: string[] = [];
      const query = {
        select: () => query,
        in(_column: string, values: string[]) {
          ids = values;
          asked.push(values.length);
          return query;
        },
        is: () => query,
        then(resolve: (answer: { data: unknown; error: null }) => void) {
          resolve({ data: ids.map((id) => ({ id, source: "off", name: { nl: id } })), error: null });
        },
      };
      return query;
    },
  } as unknown as SupabaseClient;
  const ids = Array.from({ length: 120 }, (_, index) => `p${index}`);
  const products = await productsByID(client, ids);
  expect(products.map((product) => product.id)).toEqual(ids);
  expect(Math.max(...asked)).toBeLessThanOrEqual(50);
});

// Flight mode: searching shows the products this browser knows (favourites and recent ones), as the iPhone searches
// its own copy; nothing online, and no wait on supabase-js (web phase 7).
test("withoutANetworkTheSearchShowsWhatThisBrowserKnows", async () => {
  const core = { searchKey: ({ text }: { text: string }) => ({ key: text.toLowerCase() }) } as unknown as FitlingCore;
  const known = [
    productFromRow({ id: "a", owner_id: null, source: "off", name: { nl: "Appel" }, search_name: "appel", quantity_unit: "g" }),
    productFromRow({ id: "b", owner_id: null, source: "off", name: { nl: "Brood" }, search_name: "brood", quantity_unit: "g" }),
  ];
  const client = {
    from() {
      throw new Error("the server was asked");
    },
  } as unknown as SupabaseClient;
  vi.stubGlobal("navigator", { onLine: false });
  try {
    const found = await searchProducts(client, core, "App", known);
    expect(found.own.map((product) => product.id)).toEqual(["a"]);
    expect(found.online).toEqual([]);
  } finally {
    vi.unstubAllGlobals();
  }
});

// The shared products could not be read: the user's own ones are still shown, and the failure is told next to them,
// instead of an empty list (UNFORGET S58; LogFoodViewModel keeps its local results too).
test("aFailedSharedSearchKeepsTheOwnResults", async () => {
  const core = { searchKey: ({ text }: { text: string }) => ({ key: text.toLowerCase(), pattern: text.toLowerCase() }) } as unknown as FitlingCore;
  const own = { id: "own", owner_id: "u1", source: "user", name: { nl: "Appeltaart" }, search_name: "appeltaart", quantity_unit: "g" };
  const client = {
    from() {
      let shared = false;
      const query = {
        select: () => query,
        not: () => query,
        is(column: string, value: unknown) {
          if (column === "owner_id" && value === null) shared = true;
          return query;
        },
        filter: () => query,
        limit: () => query,
        then(resolve: (answer: { data: unknown; error: unknown }) => void) {
          resolve(shared ? { data: null, error: { message: "unavailable" } } : { data: [own], error: null });
        },
      };
      return query;
    },
  } as unknown as SupabaseClient;
  const found = await searchProducts(client, core, "appel", []);
  expect(found.own.map((product) => product.id)).toEqual(["own"]);
  expect(found.online).toEqual([]);
  expect(found.onlineFailed).toBe("error.server");
});
