import { expect, test } from "vitest";
import { csv, exportFiles, exportJSON, exportTables } from "./export";

// DataExportTests on iOS. 2026-11-18, 11:06:40 UTC.
const now = new Date(1_795_000_000_000);
const user = "8c1f0a52-5d0e-4c2b-9a51-6f2f7f5d2a10";

function water(ml: number, deleted = false) {
  return { id: crypto.randomUUID(), user_id: user, amount_ml: ml, deleted_at: deleted ? now.toISOString() : null, synced_at: now.toISOString() };
}

test("exportsTheRowsOfTheSyncedTables", () => {
  const tables = exportTables({ water_entries: [water(250), water(500)] });
  const rows = tables.find((table) => table.name === "water_entries")?.rows ?? [];
  expect(rows.map((row) => row.amount_ml).sort()).toEqual([250, 500]);
  expect(rows.every((row) => row.user_id === user)).toBe(true);
  // synced_at belongs to the server and is not part of a record.
  expect(rows.every((row) => !("synced_at" in row))).toBe(true);
});

test("leavesOutDeletedRows", () => {
  const rows = exportTables({ water_entries: [water(250), water(500, true)] })[0].rows;
  expect(rows.map((row) => row.amount_ml)).toEqual([250]);
});

test("leavesOutSharedRowsOfTablesWithAnOwner", () => {
  const rows = exportTables({
    products: [
      { owner_id: user, name: { nl: "Eigen granola" } },
      { owner_id: null, name: { nl: "Halfvolle melk" } },
    ],
  })[0].rows;
  expect(rows).toEqual([{ owner_id: user, name: { nl: "Eigen granola" } }]);
});

test("leavesOutTablesWithoutRows", () => {
  expect(exportTables({ water_entries: [], products: [{ owner_id: null }] })).toEqual([]);
});

test("jsonHoldsTheExportDateAndEveryTable", () => {
  const object = JSON.parse(exportJSON(exportTables({ water_entries: [water(250)] }), now));
  expect(object.exported_at).toBe("2026-11-18T11:06:40Z");
  expect(object.tables.water_entries).toHaveLength(1);
});

test("csvHasOneHeaderAndQuotesWhatNeedsQuoting", () => {
  const table = {
    name: "x",
    rows: [
      { b: 'say "hi"', a: "1,2", c: null },
      { a: "line\nbreak", d: 3, e: { nl: "melk" } },
    ],
  };
  const expected = "a,b,c,d,e\r\n" + '"1,2","say ""hi""",,,\r\n' + '"line\nbreak",,,3,"{""nl"":""melk""}"\r\n';
  expect(csv(table)).toBe(expected);
});

test("writesOneJSONFileAndOneCSVPerTable", () => {
  const files = exportFiles(exportTables({ water_entries: [water(250)], products: [{ owner_id: user }] }), now);
  expect(files.map((file) => file.name).sort()).toEqual(["fitling-export.json", "products.csv", "water_entries.csv"]);
});
