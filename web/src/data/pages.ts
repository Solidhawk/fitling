import { failure } from "./failure";

export type Row = Record<string, unknown>;

/** The server answers at most this many rows at a time (PostgREST max_rows). */
const page = 1000;

/**
 * Every row a query matches, page by page; the query sorts by `id`, so no row is read twice or skipped. For lists
 * that can outgrow one answer: a partner not folded in for months, a user with hundreds of workouts.
 */
export async function allRows(
  query: (from: number, to: number) => PromiseLike<{ data: Row[] | null; error: { message: string } | null }>,
): Promise<Row[]> {
  const rows: Row[] = [];
  for (let from = 0; ; from += page) {
    const { data, error } = await query(from, from + page - 1);
    if (error) throw failure(error);
    rows.push(...(data ?? []));
    if ((data ?? []).length < page) return rows;
  }
}
