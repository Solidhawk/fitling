/**
 * What went wrong talking to Supabase, as the String Catalog key the app shows: no connection, or a problem on the
 * server. supabase-js reports a failed fetch as an error object rather than throwing.
 */
export function failure(error: unknown): Error {
  const message = error instanceof Error ? error.message : String((error as { message?: unknown })?.message ?? error);
  const offline = /Failed to fetch|NetworkError|Load failed|network/i.test(message);
  return new Error(offline ? "error.network" : "error.server");
}
