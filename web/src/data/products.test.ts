import type { SupabaseClient } from "@supabase/supabase-js";
import { expect, test } from "vitest";
import { ownCopyRow, productFromRow, productsByID } from "./products";

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
