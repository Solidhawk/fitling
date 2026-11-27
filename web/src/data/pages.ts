import { failure } from "./failure";

export type Row = Record<string, unknown>;

/** The server answers at most this many rows at a time (PostgREST max_rows). */
const page = 1000;

/** A supabase-js query before its order: it can be read on from a key, sorted by that key, a page at a time. */
export interface Keyset {
  gt(column: string, value: string): Keyset;
  order(column: string): { limit(count: number): PromiseLike<{ data: Row[] | null; error: { message: string } | null }> };
}

/**
 * Every row a query matches, page by page, each page from the last id read on (keyset): a row removed or added while
 * the pages are read shifts nothing, where reading by position would skip a row (UNFORGET S42). Every row needs its
 * `key`, a unique column (its `id`, or `user_id` in a table with one row per user). For lists that can outgrow one
 * answer: a partner not folded in for months, a user with hundreds of workouts.
 */
export async function allRows(query: () => Keyset, key = "id"): Promise<Row[]> {
  const rows: Row[] = [];
  let after: string | undefined;
  for (;;) {
    const base = query();
    const { data, error } = await (after === undefined ? base : base.gt(key, after)).order(key).limit(page);
    if (error) throw failure(error);
    const found = data ?? [];
    rows.push(...found);
    if (found.length < page) return rows;
    const last = found[found.length - 1][key];
    // Without it the next page would be the first again, and again.
    if (typeof last !== "string") throw new Error(`allRows needs the ${key} of every row`);
    after = last;
  }
}
