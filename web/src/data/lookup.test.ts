import { FunctionsFetchError, FunctionsHttpError, type SupabaseClient } from "@supabase/supabase-js";
import { expect, test, vi } from "vitest";
import type { FitlingCore } from "../core/fitlingCore";
import { lookUp } from "./lookup";

// ProductLookupTests on iOS, with the server faked. 2026-11-24.
const now = new Date("2026-11-24T12:00:00Z");
const daysAgo = (days: number) => new Date(now.getTime() - days * 86_400_000).toISOString();
const gtin = "8712100849084";

/** Barcode.normalized for the codes these tests use. */
const core = {
  barcode: ({ text }: { text: string }) =>
    ({ "8712100849084": { gtin }, "036000291452": { gtin: "0036000291452" } })[text] ?? {},
} as unknown as FitlingCore;

type Row = Record<string, unknown>;
type Answer = { data: unknown; error: unknown };

function server(rows: Row[], answer: () => Answer) {
  const asked = { gtin: undefined as string | undefined, invoked: 0, read: 0 };
  const client = {
    from() {
      asked.read += 1;
      const query = {
        select: () => query,
        is: () => query,
        eq(_column: string, value: string) {
          asked.gtin = value;
          return query;
        },
        then(resolve: (answer: Answer) => void) {
          resolve({ data: rows.filter((row) => row.gtin === asked.gtin), error: null });
        },
      };
      return query;
    },
    functions: {
      async invoke() {
        asked.invoked += 1;
        return answer();
      },
    },
  } as unknown as SupabaseClient;
  return { client, asked };
}

const shared = (fetchedAt: string, name = "Hagelslag") => ({ id: `shared-${name}`, owner_id: null, source: "off", gtin, name: { nl: name }, fetched_at: fetchedAt });
const fromServer = (): Answer => ({ data: shared(daysAgo(0), "Vers"), error: null });
const notFound = (): Answer => ({ data: null, error: new FunctionsHttpError(new Response(null, { status: 404 })) });
const offline = (): Answer => ({ data: null, error: new FunctionsFetchError(new TypeError("Failed to fetch")) });

test("usesTheLocalProductWhenFresh", async () => {
  const { client, asked } = server([shared(daysAgo(1))], fromServer);
  expect(await lookUp(client, core, gtin, now)).toMatchObject({ kind: "found", product: { id: "shared-Hagelslag" } });
  expect(asked.invoked).toBe(0);
});

test("asksTheServerWhenStale", async () => {
  const { client, asked } = server([shared(daysAgo(40))], fromServer);
  expect(await lookUp(client, core, gtin, now)).toMatchObject({ kind: "found", product: { id: "shared-Vers" } });
  expect(asked.invoked).toBe(1);
});

test("keepsTheStaleProductWhenOffline", async () => {
  const { client } = server([shared(daysAgo(40))], offline);
  expect(await lookUp(client, core, gtin, now)).toMatchObject({ kind: "found", product: { id: "shared-Hagelslag" } });
});

test("reportsNotFound", async () => {
  const { client } = server([], notFound);
  expect(await lookUp(client, core, gtin, now)).toEqual({ kind: "notFound", gtin });
});

test("offlineWithoutACopyIsUnavailable", async () => {
  const { client } = server([], offline);
  expect(await lookUp(client, core, gtin, now)).toEqual({ kind: "unavailable", gtin });
});

test("invalidBarcodeNeverReachesTheServer", async () => {
  const { client, asked } = server([], fromServer);
  expect(await lookUp(client, core, "8712100849085", now)).toEqual({ kind: "invalid" });
  expect(asked).toMatchObject({ invoked: 0, read: 0 });
});

test("aUPCCodeIsLookedUpUnderItsThirteenDigitKey", async () => {
  const { client, asked } = server([], notFound);
  expect(await lookUp(client, core, "036000291452", now)).toEqual({ kind: "notFound", gtin: "0036000291452" });
  expect(asked.gtin).toBe("0036000291452");
});

test("theUsersOwnProductComesFirstAndNeverExpires", async () => {
  const own = { id: "own", owner_id: "u1", source: "user", gtin, name: { nl: "Mijn hagelslag" }, fetched_at: null };
  const { client, asked } = server([shared(daysAgo(1)), own], fromServer);
  expect(await lookUp(client, core, gtin, now)).toMatchObject({ kind: "found", product: { id: "own" } });
  expect(asked.invoked).toBe(0);
});

// Flight mode: the scan says "no connection" at once, without first waiting on supabase-js (web phase 7).
test("withoutANetworkAScanSaysSoAtOnce", async () => {
  const { client, asked } = server([shared(daysAgo(1))], fromServer);
  vi.stubGlobal("navigator", { onLine: false });
  try {
    expect(await lookUp(client, core, gtin, now)).toEqual({ kind: "unavailable", gtin });
    expect(asked).toMatchObject({ invoked: 0, read: 0 });
  } finally {
    vi.unstubAllGlobals();
  }
});
