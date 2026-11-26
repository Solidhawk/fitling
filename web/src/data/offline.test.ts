import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { flush, forgetOffline, kept, notSaved, rowsBetween, send, setOfflineUser, takeRefused, waiting } from "./offline";

// Without a connection (web phase 7): the last answer to each read, the days of the diary and the writes still to be
// sent, per user, as the iPhone keeps its own database. diary.test.ts sends the same rows to a real server.

let stored: Map<string, string>;

beforeEach(() => {
  stored = new Map();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
    removeItem: (key: string) => stored.delete(key),
    key: (index: number) => [...stored.keys()][index] ?? null,
    get length() {
      return stored.size;
    },
  });
  setOfflineUser("user-1");
});

afterEach(() => {
  setOfflineUser(undefined);
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

type Answer = { error: { message: string; code?: string } | null };

const ok: Answer = { error: null };
const noConnection: Answer = { error: { message: "TypeError: Failed to fetch" } };
const lost = () => Promise.reject(new Error("error.network"));

/** A server that answers each write in turn from `answers`, then with `rest`, and remembers what it was sent. */
function server(answers: Answer[], rest: Answer = ok) {
  const sent: { table: string; kind: string; row: Record<string, unknown> }[] = [];
  const next = () => Promise.resolve(answers.shift() ?? rest);
  const client = {
    from: (table: string) => ({
      insert: (row: Record<string, unknown>) => {
        sent.push({ table, kind: "insert", row });
        return next();
      },
      update: (row: Record<string, unknown>) => ({
        eq: (_column: string, id: string) => {
          sent.push({ table, kind: "update", row: { id, ...row } });
          return next();
        },
      }),
    }),
  };
  return { client: client as unknown as SupabaseClient, sent };
}

const down = () => server([], noConnection).client;

test("readsAreKeptForWithoutAConnection", async () => {
  expect(await kept("profile", async () => ({ kcal: 2000 }))).toEqual({ kcal: 2000 });
  expect(await kept("profile", lost)).toEqual({ kcal: 2000 });
  // A server that answers with an error is not "no connection": that error stays.
  await expect(kept("profile", () => Promise.reject(new Error("error.server")))).rejects.toThrow("error.server");
  // Nothing kept yet: no connection stays no connection.
  await expect(kept("periods", lost)).rejects.toThrow("error.network");
});

test("writesWaitAndGoInOrder", async () => {
  const first = { id: "a", consumed_on: "2026-11-25", amount_ml: 250 };
  const second = { id: "b", consumed_on: "2026-11-25", amount_ml: 250 };
  await send(down(), { table: "water_entries", kind: "insert", row: first });
  await send(down(), { table: "water_entries", kind: "insert", row: second });
  expect(waiting().map((write) => write.row.id)).toEqual(["a", "b"]);
  // Back online: oldest first, each row exactly as it was made.
  const up = server([]);
  await flush(up.client);
  expect(up.sent.map((write) => write.row)).toEqual([first, second]);
  expect(waiting()).toEqual([]);
});

test("aRowTheServerAlreadyHasCountsAsSent", async () => {
  // The answer to an earlier try got lost: the same id again is a duplicate (23505), not an error.
  const again = server([{ error: { message: "duplicate key value", code: "23505" } }]);
  await send(again.client, { table: "food_entries", kind: "insert", row: { id: "a" } });
  expect(waiting()).toEqual([]);
});

test("aRefusedWriteIsReportedAndLeavesTheQueue", async () => {
  const refusing = server([{ error: { message: "new row violates check constraint", code: "23514" } }]);
  await expect(send(refusing.client, { table: "food_entries", kind: "insert", row: { id: "a" } })).rejects.toThrow("error.server");
  expect(waiting()).toEqual([]);
});

test("aWriteTheServerCannotTakeYetStays", async () => {
  // A token that ran out or a server that is down: the write waits, and logging it worked.
  const notNow = server([{ error: { message: "JWT expired", code: "PGRST301" } }]);
  await send(notNow.client, { table: "food_entries", kind: "insert", row: { id: "a" } });
  expect(waiting().map((write) => write.row.id)).toEqual(["a"]);
});

test("anOlderRefusalIsNotReportedForANewWrite", async () => {
  await send(down(), { table: "food_entries", kind: "insert", row: { id: "old" } });
  const refusingTheOld = server([{ error: { message: "violates check constraint", code: "23514" } }]);
  await send(refusingTheOld.client, { table: "food_entries", kind: "insert", row: { id: "new" } });
  expect(refusingTheOld.sent.map((write) => write.row.id)).toEqual(["old", "new"]);
  expect(waiting()).toEqual([]);
});

test("updatesAreSentAsUpdates", async () => {
  const up = server([]);
  await send(up.client, { table: "food_entries", kind: "update", row: { id: "a", deleted_at: "x", updated_at: "x" } });
  expect(up.sent).toEqual([{ table: "food_entries", kind: "update", row: { id: "a", deleted_at: "x", updated_at: "x" } }]);
});

const day = "2026-11-25";
const eaten = { id: "a", consumed_on: day, kcal: 250 };
const logged = { id: "b", consumed_on: day, kcal: 100 };

test("aDayShowsWhatWasLoggedHereWithoutAConnection", async () => {
  expect(await rowsBetween("food_entries", day, day, async () => [eaten])).toEqual([eaten]);
  await send(down(), { table: "food_entries", kind: "insert", row: logged });
  expect(await rowsBetween("food_entries", day, day, lost)).toEqual([eaten, logged]);
  await send(down(), { table: "food_entries", kind: "update", row: { id: "a", deleted_at: "x", updated_at: "x" } });
  expect(await rowsBetween("food_entries", day, day, lost)).toEqual([logged]);
});

test("theServerGetsWhatItDoesNotHaveYet", async () => {
  await rowsBetween("food_entries", day, day, async () => [eaten]);
  await send(down(), { table: "food_entries", kind: "insert", row: logged });
  await send(down(), { table: "food_entries", kind: "update", row: { id: "a", deleted_at: "x", updated_at: "x" } });
  // The server answers without what still waits: the day shows it all the same, and keeps it.
  expect(await rowsBetween("food_entries", day, day, async () => [eaten])).toEqual([logged]);
  expect(await rowsBetween("food_entries", day, day, lost)).toEqual([logged]);
});

test("aWriteSentWhileReadingIsNotLost", async () => {
  await rowsBetween("food_entries", day, day, async () => []);
  // The read leaves before the write arrives and comes back without it.
  const read = rowsBetween("food_entries", day, day, async () => {
    await send(server([]).client, { table: "food_entries", kind: "insert", row: logged });
    return [];
  });
  expect(await read).toEqual([logged]);
  expect(await rowsBetween("food_entries", day, day, lost)).toEqual([logged]);
});

test("aDayNeverReadIsNotShownAsEmpty", async () => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(2026, 10, 24, 12));
  await rowsBetween("food_entries", "2026-11-23", "2026-11-24", async () => []);
  // A day before the last read that was never read itself: unknown.
  await expect(rowsBetween("food_entries", "2026-11-20", "2026-11-20", lost)).rejects.toThrow("error.network");
  // The next morning: the new day had nothing yet, and what is logged here shows.
  vi.setSystemTime(new Date(2026, 10, 25, 8));
  await send(down(), { table: "food_entries", kind: "insert", row: logged });
  expect(await rowsBetween("food_entries", "2026-11-25", "2026-11-25", lost)).toEqual([logged]);
  expect(await rowsBetween("food_entries", "2026-11-23", "2026-11-25", lost)).toEqual([logged]);
});

test("anotherUserErasesWhatWasKept", async () => {
  await send(down(), { table: "water_entries", kind: "insert", row: { id: "a", consumed_on: day } });
  await kept("profile", async () => ({ kcal: 2000 }));
  setOfflineUser("user-2");
  expect(waiting()).toEqual([]);
  await expect(kept("profile", lost)).rejects.toThrow("error.network");
  setOfflineUser("user-1");
  expect(waiting()).toEqual([]);
});

test("aSessionThatEndsByItselfKeepsWhatWaits", async () => {
  await send(down(), { table: "water_entries", kind: "insert", row: { id: "a", consumed_on: day } });
  setOfflineUser(undefined);
  setOfflineUser("user-1");
  expect(waiting().map((write) => write.row.id)).toEqual(["a"]);
});

test("signingOutOnPurposeForgetsEverything", async () => {
  await send(down(), { table: "water_entries", kind: "insert", row: { id: "a", consumed_on: day } });
  await kept("profile", async () => ({ kcal: 2000 }));
  forgetOffline();
  expect([...stored.keys()].filter((key) => key.startsWith("fitling.offline."))).toEqual([]);
});

test("aBrowserThatKeepsNothingSendsStraightAway", async () => {
  vi.stubGlobal("localStorage", undefined);
  const up = server([]);
  await send(up.client, { table: "water_entries", kind: "insert", row: { id: "a", consumed_on: day } });
  expect(up.sent).toHaveLength(1);
  await expect(send(down(), { table: "water_entries", kind: "insert", row: { id: "b", consumed_on: day } })).rejects.toThrow("error.network");
});

// Flight mode: the browser knows there is no network. supabase-js would first spend half a minute trying to refresh an
// expired token; the server is not asked at all, and what this browser has comes at once.
test("withoutANetworkTheServerIsNotAsked", async () => {
  await kept("profile", async () => ({ kcal: 2000 }));
  await rowsBetween("food_entries", day, day, async () => [eaten]);
  vi.stubGlobal("navigator", { onLine: false });
  const never = () => Promise.reject(new Error("the server was asked"));
  expect(await kept("profile", never)).toEqual({ kcal: 2000 });
  expect(await rowsBetween("food_entries", day, day, never)).toEqual([eaten]);
  const asked = server([]);
  await send(asked.client, { table: "food_entries", kind: "insert", row: logged });
  await flush(asked.client);
  expect(asked.sent).toEqual([]);
  expect(waiting().map((write) => write.row.id)).toEqual(["b"]);
  expect(await rowsBetween("food_entries", day, day, never)).toEqual([eaten, logged]);
});

// Fable's review of phase 7: what the server turns down later, in a round nobody waits for, is told once on Vandaag.
test("aWriteRefusedLaterIsToldOnce", async () => {
  await send(down(), { table: "food_entries", kind: "insert", row: { id: "a", consumed_on: day } });
  await flush(server([{ error: { message: "numeric field overflow", code: "22003" } }]).client);
  expect(waiting()).toEqual([]);
  expect(takeRefused()).toBe(1);
  expect(takeRefused()).toBe(0);
});

// A write the server keeps turning down for another reason (a token, a policy) waits, and Vandaag says that not
// everything is saved; once it goes through, that is over.
test("aWriteThatKeepsWaitingIsShown", async () => {
  await send(down(), { table: "food_entries", kind: "insert", row: { id: "a", consumed_on: day } });
  expect(notSaved()).toBe(false);
  await flush(server([], { error: { message: "permission denied", code: "42501" } }).client);
  expect(notSaved()).toBe(true);
  await flush(down());
  expect(notSaved()).toBe(true);
  await flush(server([]).client);
  expect(notSaved()).toBe(false);
  expect(waiting()).toEqual([]);
});
