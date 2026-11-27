import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { loadPartner, type Partner, savePartner } from "./creature";
import { keep, setOfflineUser } from "./offline";

// The partner this browser keeps for without a connection (web phase 7); creature.test.ts saves to a real server.

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
  vi.unstubAllGlobals();
});

// A change on the partner tab lands in the kept partner too: opened without a connection, it has the new name, colour,
// voice and what it wears, instead of how it was read last (UNFORGET S50).
test("aSavedChangeIsInTheKeptPartner", async () => {
  const partner: Partner = {
    species: "owl",
    name: "Uil",
    items: [],
    state: { species: "owl", colorIndex: 0, tone: "sweet", createdOn: "2026-11-01", bodyShape: 0.3, xp: 30_000, offTargetDays: 0 },
  };
  keep("partner", partner);
  const client = { from: () => ({ update: () => ({ eq: () => Promise.resolve({ error: null }) }) }) } as unknown as SupabaseClient;
  await savePartner(client, "user-1", { name: "Pip", items: ["crown"] }, new Date());
  await savePartner(client, "user-1", { colorIndex: 2, tone: "cheeky" }, new Date());
  vi.stubGlobal("navigator", { onLine: false });
  expect(await loadPartner(client, "user-1")).toEqual({
    ...partner,
    name: "Pip",
    items: ["crown"],
    state: { ...partner.state, colorIndex: 2, tone: "cheeky" },
  });
});
