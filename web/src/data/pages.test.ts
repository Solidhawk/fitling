import { expect, test } from "vitest";
import { allRows, type Keyset } from "./pages";

/** A query over `rows` that answers a page from an id on, sorted by id. */
function query(rows: Record<string, unknown>[]): () => Keyset {
  return () => {
    let after: string | undefined;
    const builder = {
      gt(_column: string, value: string) {
        after = value;
        return builder;
      },
      order: () => ({
        limit: (count: number) =>
          Promise.resolve({ data: rows.filter((row) => after === undefined || String(row.id) > after).slice(0, count), error: null }),
      }),
    };
    return builder as unknown as Keyset;
  };
}

// Pages are read on from the last id: rows without their id would ask for the first page again and again, so the
// reading stops with an error instead (review of PR #61).
test("rowsWithoutTheirIdStopTheReading", async () => {
  const rows = Array.from({ length: 1000 }, (_, index) => ({ name: `rij ${index}` }));
  await expect(allRows(query(rows))).rejects.toThrow("the id of every row");
});
