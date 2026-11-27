import { failure } from "./failure";

export type Row = Record<string, unknown>;

/** The server answers at most this many rows at a time (PostgREST max_rows). */
const page = 1000;

/** A supabase-js query before its order: it can be read on from an id, sorted by id, a page at a time. */
export interface Keyset {
  gt(column: "id", value: string): Keyset;
  order(column: "id"): { limit(count: number): PromiseLike<{ data: Row[] | null; error: { message: string } | null }> };
}

/**
 * Every row a query matches, page by page, each page from the last id read on (keyset): a row removed or added while
 * the pages are read shifts nothing, where reading by position would skip a row (UNFORGET S42). Every row needs its
 * `id`. For lists that can outgrow one answer: a partner not folded in for months, a user with hundreds of workouts.
 */
export async function allRows(query: () => Keyset): Promise<Row[]> {
  const rows: Row[] = [];
  let after: string | undefined;
  for (;;) {
    const base = query();
    const { data, error } = await (after === undefined ? base : base.gt("id", after)).order("id").limit(page);
    if (error) throw failure(error);
    const found = data ?? [];
    rows.push(...found);
    if (found.length < page) return rows;
    after = found[found.length - 1].id as string;
  }
}
