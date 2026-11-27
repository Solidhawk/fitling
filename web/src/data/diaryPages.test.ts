import type { SupabaseClient } from "@supabase/supabase-js";
import { expect, test } from "vitest";
import { entriesBetween, workoutDaysBetween } from "./diary";

// Review Focus: a partner not folded in for a long time reads every entry since, also past the server's 1000 rows.
/** A client whose server answers at most 1000 rows, from an id on, and only when they are sorted by id. */
function pagedClient(rows: { id: string }[]): SupabaseClient {
  return {
    from() {
      let ordered = false;
      let after: string | undefined;
      const query = {
        select: () => query,
        gte: () => query,
        lte: () => query,
        is: () => query,
        not: () => query,
        gt(_column: string, value: string) {
          after = value;
          return query;
        },
        order(column: string) {
          ordered = column === "id";
          return query;
        },
        limit(count: number) {
          expect(ordered).toBe(true);
          return Promise.resolve({ data: rows.filter((row) => after === undefined || row.id > after).slice(0, Math.min(count, 1000)), error: null });
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

// An entry removed on another device while the pages are read moves every later row one place forward: counted by
// position, the next page would skip one. Read on from the last id, none is skipped (UNFORGET S42).
test("anEntryRemovedWhileReadingSkipsNoOther", async () => {
  let live = Array.from({ length: 2500 }, (_, index) => ({
    id: String(index).padStart(5, "0"),
    consumed_on: "2026-11-01",
    meal: "lunch",
    name: "Brood",
    quantity: 100,
    quantity_unit: "g",
    kcal: 250,
    updated_at: "2026-11-01T12:00:00Z",
  }));
  let pages = 0;
  const answer = (data: object[]) => {
    pages += 1;
    if (pages === 1) live = live.filter((row) => row.id !== "00010");
    return Promise.resolve({ data, error: null });
  };
  const client = {
    from() {
      let after: string | undefined;
      const query = {
        select: () => query,
        gte: () => query,
        lte: () => query,
        is: () => query,
        order: () => query,
        gt(_column: string, value: string) {
          after = value;
          return query;
        },
        limit: (count: number) => answer(live.filter((row) => after === undefined || row.id > after).slice(0, count)),
      };
      return query;
    },
  } as unknown as SupabaseClient;
  const read = await entriesBetween(client, "2026-10-01", "2026-11-24");
  expect(read).toHaveLength(2500);
  expect(read.some((entry) => entry.id === "01000")).toBe(true);
});
