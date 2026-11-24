import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * All of the user's own data, as one JSON file and one CSV file per table (DataExport.swift). The tables are those
 * the app syncs (SyncTables.all), with the column names of the database. Deleted rows and shared rows (the product
 * cache, the built-in exercises and recipes) are left out.
 */

type Row = Record<string, unknown>;

export interface Table {
  name: string;
  rows: Row[];
}

/** In the order of SyncTables.all; the tables that hold shared rows next to the user's own name their owner column. */
const tables: [name: string, owner?: string][] = [
  ["profiles"],
  ["target_history"],
  ["products", "owner_id"],
  ["recipes", "owner_id"],
  ["recipe_ingredients", "owner_id"],
  ["food_entries"],
  ["water_entries"],
  ["favorite_products"],
  ["creatures"],
  ["exercises", "owner_id"],
  ["programs", "owner_id"],
  ["program_days", "owner_id"],
  ["program_exercises", "owner_id"],
  ["exercise_settings"],
  ["workout_sessions"],
  ["workout_sets"],
  ["body_measurements"],
  ["menu_preferences"],
  ["excluded_ingredients"],
  ["meal_plan_entries"],
  ["shopping_lists"],
  ["shopping_items"],
  ["favorite_supermarkets"],
];

const owners = new Map(tables.filter(([, owner]) => owner).map(([name, owner]) => [name, owner as string]));

export const jsonFileName = "fitling-export.json";

/** The rows as a record carries them: without deleted or shared rows, without the server's `synced_at`. */
export function exportTables(rowsByTable: Record<string, Row[]>): Table[] {
  return Object.entries(rowsByTable)
    .map(([name, rows]) => {
      const owner = owners.get(name);
      const kept = rows
        .filter((row) => row.deleted_at == null && (owner === undefined || row[owner] != null))
        .map(({ synced_at: _synced, ...record }) => record);
      return { name, rows: kept };
    })
    .filter((table) => table.rows.length > 0);
}

/** A copy with the keys of every object sorted, as JSONSerialization's .sortedKeys. */
function sorted(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sorted);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value as Row)
        .sort()
        .map((key) => [key, sorted((value as Row)[key])]),
    );
  }
  return value;
}

export function exportJSON(exported: Table[], exportedAt: Date): string {
  const byName = Object.fromEntries(exported.map((table) => [table.name, table.rows]));
  // ISO 8601 to the second, as Date.formatted(.iso8601): "2026-11-18T11:06:40Z".
  const at = exportedAt.toISOString().replace(/\.\d{3}Z$/, "Z");
  return JSON.stringify(sorted({ exported_at: at, tables: byName }), null, 2);
}

/** As NSNumber.stringValue and JSONSerialization give a value: booleans as 1 and 0, nested values as JSON text. */
function text(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") return value;
  if (typeof value === "boolean") return value ? "1" : "0";
  if (typeof value === "number") return String(value);
  return JSON.stringify(sorted(value));
}

function field(value: string): string {
  return /[,"\n\r]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
}

/** RFC 4180: a header with every column of the table, CRLF line ends, quotes around a value that needs them. */
export function csv(table: Table): string {
  const columns = [...new Set(table.rows.flatMap((row) => Object.keys(row)))].sort();
  const lines = [columns.map(field).join(","), ...table.rows.map((row) => columns.map((column) => field(text(row[column]))).join(","))];
  return lines.map((line) => `${line}\r\n`).join("");
}

export function exportFiles(exported: Table[], exportedAt: Date): File[] {
  return [
    new File([exportJSON(exported, exportedAt)], jsonFileName, { type: "application/json" }),
    ...exported.map((table) => new File([csv(table)], `${table.name}.csv`, { type: "text/csv" })),
  ];
}

/** Reads every synced table; row level security returns only the user's own rows and the shared ones. */
export async function fetchTables(client: SupabaseClient): Promise<Record<string, Row[]>> {
  const results = await Promise.all(
    tables.map(async ([name, owner]) => {
      const query = client.from(name).select("*");
      const { data, error } = await (owner ? query.not(owner, "is", null) : query);
      if (error) throw new Error("account.export.failed");
      return [name, data as Row[]] as const;
    }),
  );
  return Object.fromEntries(results);
}

/**
 * Offers the files to save or share. Where the browser can share files (Safari and Chrome on a phone) that is the
 * share sheet, as on iOS; elsewhere each file is downloaded.
 */
export async function deliver(files: File[]): Promise<void> {
  if (navigator.canShare?.({ files })) {
    try {
      await navigator.share({ files });
      return;
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return;
    }
  }
  for (const file of files) {
    const url = URL.createObjectURL(file);
    const link = document.createElement("a");
    link.href = url;
    link.download = file.name;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
}
