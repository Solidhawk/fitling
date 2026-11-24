import type { SupabaseClient } from "@supabase/supabase-js";
import { expect, test } from "vitest";
import { entriesBetween, workoutDaysBetween } from "./diary";

// Review Focus: a partner not folded in for a long time reads every entry since, also past the server's 1000 rows.
/** A client whose server answers at most 1000 rows, and only when they are sorted, so pages do not overlap. */
function pagedClient(rows: object[]): SupabaseClient {
  return {
    from() {
      let ordered = false;
      const query = {
        select: () => query,
        gte: () => query,
        lte: () => query,
        is: () => query,
        not: () => query,
        order() {
          ordered = true;
          return query;
        },
        range(from: number, to: number) {
          expect(ordered).toBe(true);
          return Promise.resolve({ data: rows.slice(from, Math.min(to + 1, from + 1000)), error: null });
        },
      };
      return query;
    },
  } as unknown as SupabaseClient;
}

test("manyDaysAreReadInPages", async () => {
  const rows = Array.from({ length: 2500 }, (_, index) => ({
    id: String(index).padStart(5, "0"),
    consumed_on: "2026-11-01",
    meal: "lunch",
    name: "Brood",
    quantity: 100,
    quantity_unit: "g",
    kcal: 250,
    updated_at: "2026-11-01T12:00:00Z",
  }));
  expect(await entriesBetween(pagedClient(rows), "2026-10-01", "2026-11-24")).toHaveLength(2500);
  const sessions = Array.from({ length: 1500 }, (_, index) => ({ id: String(index).padStart(5, "0"), performed_on: `day-${index}` }));
  expect(await workoutDaysBetween(pagedClient(sessions), "2022-01-01", "2026-11-24")).toHaveLength(1500);
});
