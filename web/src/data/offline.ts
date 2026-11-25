import type { SupabaseClient } from "@supabase/supabase-js";
import type { IsoDay } from "../core/fitlingCore";
import { addDays, today } from "../day";
import { failure } from "./failure";

/**
 * Without a connection (web phase 7), as the iPhone keeps its own database: the last answer to each read, the days of
 * the diary as this browser last knew them, and the writes still to be sent. Every write goes out later exactly as it
 * was made, with the same id and updated_at, so the server's last-writer-wins rules treat it as any other device's.
 * Everything is kept per user in localStorage: written before the request leaves, and there after a reload.
 */

export type Table = "food_entries" | "water_entries";
export type Row = Record<string, unknown> & { id: string };
export interface Write {
  table: Table;
  kind: "insert" | "update";
  row: Row;
}
interface Stored extends Write {
  key: string;
  /** When the server took it: a read that started earlier may not have it yet. */
  sentAt?: number;
}
interface Days {
  /** The last day a read of the server came back: days after it had nothing on the server yet. */
  fetchedOn?: IsoDay;
  days: Record<IsoDay, Row[]>;
}

const prefix = "fitling.offline.";
/** Days of the diary kept: the partner's two weeks and a few weeks of paging back. */
const keptDays = 40;
/** How long a sent write still counts for a read that was under way while it was sent. */
const sentWindowMs = 10 * 60 * 1000;

let user: string | undefined;

function storageKey(name: string): string | undefined {
  return user ? `${prefix}${user}.${name}` : undefined;
}

function load<T>(name: string): T | undefined {
  const key = storageKey(name);
  if (!key) return undefined;
  try {
    const text = localStorage.getItem(key);
    return text === null ? undefined : (JSON.parse(text) as T);
  } catch {
    return undefined;
  }
}

/** False when the browser keeps nothing (storage off, or full). */
function store(name: string, value: unknown): boolean {
  const key = storageKey(name);
  if (!key) return false;
  try {
    localStorage.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    return false;
  }
}

function keys(): string[] {
  try {
    return Array.from({ length: localStorage.length }, (_, index) => localStorage.key(index)).filter((key): key is string => key?.startsWith(prefix) ?? false);
  } catch {
    return [];
  }
}

function remove(key: string) {
  try {
    localStorage.removeItem(key);
  } catch {
    // Nothing kept, nothing to remove.
  }
}

/**
 * The signed-in user, or undefined when nobody is. What another user left behind goes, as RootViewModel on iOS erases
 * it for another user; a session that ended by itself is no reason, and the same user gets it back.
 */
export function setOfflineUser(userID: string | undefined): void {
  user = userID;
  if (!userID) return;
  for (const key of keys()) if (!key.startsWith(`${prefix}${userID}.`)) remove(key);
}

/** Signing out or deleting the account on purpose erases everything kept in this browser, as on iOS. */
export function forgetOffline(): void {
  for (const key of keys()) remove(key);
}

function offline(error: unknown): boolean {
  return error instanceof Error && error.message === "error.network";
}

/** The answer of `read`, kept; without a connection the last answer kept, when there is one. */
export async function kept<T>(name: string, read: () => Promise<T>): Promise<T> {
  try {
    const value = await read();
    keep(name, value);
    return value;
  } catch (error) {
    const stored = offline(error) ? load<{ value?: T }>(`read.${name}`) : undefined;
    if (stored && "value" in stored) return stored.value as T;
    throw error;
  }
}

/** A newer answer than the last read, for example a partner the app just folded days into. */
export function keep(name: string, value: unknown): void {
  store(`read.${name}`, { value });
}

function stored(): Stored[] {
  return load<Stored[]>("writes") ?? [];
}

/** The writes that have not reached the server yet, oldest first. */
export function waiting(): Write[] {
  return stored()
    .filter((write) => write.sentAt === undefined)
    .map(({ table, kind, row }) => ({ table, kind, row }));
}

/** The error of one write, or null when it arrived; the same row again (23505) arrived the first time. */
async function deliver(client: SupabaseClient, write: Write): Promise<{ message: string; code?: string } | null> {
  try {
    if (write.kind === "insert") {
      const { error } = await client.from(write.table).insert(write.row);
      return error && error.code !== "23505" ? error : null;
    }
    const { id, ...changes } = write.row;
    const { error } = await client.from(write.table).update(changes).eq("id", id);
    return error;
  } catch (error) {
    return { message: error instanceof Error ? error.message : String(error) };
  }
}

/**
 * The server can never take this write: its data breaks a rule (SQLSTATE class 22 or 23). Anything else, a token that
 * ran out or a server that is down, can pass later, so the write stays.
 */
function refused(error: { code?: string }): boolean {
  return /^2[23]/.test(error.code ?? "");
}

function rewrite(change: (writes: Stored[]) => Stored[]) {
  store("writes", change(stored()));
}

let sending: Promise<void> = Promise.resolve();
/** Writes the server refused for good, by key, for the `send` that made them to report. */
const refusals = new Map<string, Error>();

/**
 * Sends the waiting writes, oldest first, one round at a time. Without a connection, or when the server cannot take
 * them yet, they stay for the next round; a write the server refuses for good is dropped.
 */
export function flush(client: SupabaseClient): Promise<void> {
  const round = sending.then(() => sendWaiting(client));
  sending = round.catch(() => undefined);
  return round;
}

async function sendWaiting(client: SupabaseClient): Promise<void> {
  const owner = user;
  // Each write once per round, also when the browser cannot store that it was sent.
  const tried = new Set<string>();
  while (owner && user === owner) {
    const next = stored().find((write) => write.sentAt === undefined && !tried.has(write.key));
    if (!next) return;
    tried.add(next.key);
    const error = await deliver(client, next);
    if (user !== owner) return;
    if (error && !refused(error)) return;
    if (error) {
      refusals.set(next.key, failure(error));
      rewrite((writes) => writes.filter((write) => write.key !== next.key));
      if (next.kind === "insert") forgetRow(next.table, next.row.id);
    } else {
      const now = Date.now();
      rewrite((writes) =>
        writes
          .map((write) => (write.key === next.key ? { ...write, sentAt: now } : write))
          .filter((write) => write.sentAt === undefined || write.sentAt > now - sentWindowMs),
      );
    }
  }
}

/**
 * Sends a write, or keeps it until there is a connection; the diary shows it right away either way. Throws only when
 * the server refuses this write for good. A browser that keeps nothing sends it straight away, as before.
 */
export async function send(client: SupabaseClient, write: Write): Promise<void> {
  const key = crypto.randomUUID();
  if (!store("writes", [...stored(), { ...write, key }])) {
    const error = await deliver(client, write);
    if (error) throw failure(error);
    return;
  }
  applyToDays(write);
  await flush(client);
  const refusal = refusals.get(key);
  refusals.delete(key);
  if (refusal) throw refusal;
}

function daysOf(table: Table): Days {
  return load<Days>(`days.${table}`) ?? { days: {} };
}

function storeDays(table: Table, kept: Days) {
  const newest = Object.keys(kept.days).sort().slice(-keptDays);
  store(`days.${table}`, { fetchedOn: kept.fetchedOn, days: Object.fromEntries(newest.map((day) => [day, kept.days[day]])) });
}

function known(kept: Days, day: IsoDay): boolean {
  return day in kept.days || (kept.fetchedOn !== undefined && day > kept.fetchedOn);
}

function dates(first: IsoDay, last: IsoDay): IsoDay[] {
  const all: IsoDay[] = [];
  for (let day = first; day <= last; day = addDays(day, 1)) all.push(day);
  return all;
}

/** One write on a set of rows: a new row is added once, a change goes into the row it is for. */
function applied(rows: Row[], write: Write): Row[] {
  if (write.kind === "insert") return rows.some((row) => row.id === write.row.id) ? rows : [...rows, write.row];
  return rows.flatMap((row) => {
    if (row.id !== write.row.id) return [row];
    const changed = { ...row, ...write.row };
    return changed.deleted_at ? [] : [changed];
  });
}

function applyToDays(write: Write) {
  const kept = daysOf(write.table);
  if (write.kind === "insert") {
    const day = write.row.consumed_on as IsoDay;
    // A day this browser never read stays unknown: the write shows once the day is read.
    if (!known(kept, day)) return;
    kept.days[day] = applied(kept.days[day] ?? [], write);
  } else {
    for (const day of Object.keys(kept.days)) kept.days[day] = applied(kept.days[day], write);
  }
  storeDays(write.table, kept);
}

function forgetRow(table: Table, id: string) {
  const kept = daysOf(table);
  for (const day of Object.keys(kept.days)) kept.days[day] = kept.days[day].filter((row) => row.id !== id);
  storeDays(table, kept);
}

/**
 * The rows of `table` from `first` through `last` (by consumed_on): from the server with the writes it does not have
 * yet, or without a connection as this browser last knew them. A day it never read is not shown as an empty day.
 */
export async function rowsBetween(table: Table, first: IsoDay, last: IsoDay, fetch: () => Promise<Row[]>): Promise<Row[]> {
  const started = Date.now();
  let fetched: Row[];
  try {
    fetched = await fetch();
  } catch (error) {
    if (!offline(error) || !user) throw error;
    const kept = daysOf(table);
    const range = dates(first, last);
    if (!range.every((day) => known(kept, day))) throw error;
    return range.flatMap((day) => kept.days[day] ?? []);
  }
  if (!user) return fetched;
  const pending = stored().filter((write) => write.table === table && (write.sentAt === undefined || write.sentAt >= started));
  const rows = pending
    .filter((write) => write.kind === "update" || ((write.row.consumed_on as IsoDay) >= first && (write.row.consumed_on as IsoDay) <= last))
    .reduce(applied, fetched);
  const kept = daysOf(table);
  for (const day of dates(first, last)) kept.days[day] = rows.filter((row) => row.consumed_on === day);
  const now = today();
  if (kept.fetchedOn === undefined || now > kept.fetchedOn) kept.fetchedOn = now;
  storeDays(table, kept);
  return rows;
}
