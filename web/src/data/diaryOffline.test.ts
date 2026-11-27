import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { favoriteProducts, isFavorite, setFavorite } from "./diary";
import { keep, setOfflineUser } from "./offline";
import type { Product } from "./products";

// The favourites this browser keeps for without a connection (web phase 7); diary.test.ts sets them on a real server.

let stored: Map<string, string>;

beforeEach(() => {
  stored = new Map();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
    removeItem: (key: string) => stored.delete(key),
    key: (index: number) => [...stored.keys()][index] ?? null,
    get length() {
      return stored.size;
    },
  });
  setOfflineUser("user-1");
});

afterEach(() => {
  setOfflineUser(undefined);
  vi.unstubAllGlobals();
});

function product(id: string): Product {
  return { id, ownerID: null, source: "off", name: { nl: id }, searchName: id, quantityUnit: "g", kcal100: 100 };
}

/** A server on which the product has the favourite rows `rows`, and every write succeeds. */
function server(rows: { id: string; product_id: string }[]): SupabaseClient {
  const query = {
    is: () => query,
    eq: () => query,
    then: (resolve: (answer: unknown) => void) => resolve({ data: rows, error: null }),
  };
  return {
    from: () => ({
      select: () => query,
      insert: () => Promise.resolve({ error: null }),
      update: () => ({ in: () => Promise.resolve({ error: null }) }),
    }),
  } as unknown as SupabaseClient;
}

// A tap on the star lands in what this browser keeps: opened without a connection, the portion and the log sheet show
// it, instead of how the favourites were read last (review of PR #63).
test("aTappedStarIsInTheKeptFavorites", async () => {
  const yoghurt = product("yoghurt");
  const bread = product("bread");
  keep("favoriteIDs", [bread.id]);
  keep("favorites", [bread]);
  await setFavorite(server([]), "user-1", yoghurt, true, new Date());
  vi.stubGlobal("navigator", { onLine: false });
  expect(await isFavorite(server([]), yoghurt.id)).toBe(true);
  expect(await favoriteProducts(server([]))).toEqual([yoghurt, bread]);

  vi.stubGlobal("navigator", { onLine: true });
  await setFavorite(server([{ id: "row-1", product_id: yoghurt.id }]), "user-1", yoghurt, false, new Date());
  vi.stubGlobal("navigator", { onLine: false });
  expect(await isFavorite(server([]), yoghurt.id)).toBe(false);
  expect(await favoriteProducts(server([]))).toEqual([bread]);
});
