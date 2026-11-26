import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, expect, test, vi } from "vitest";
import type { FitlingCore, PartnerDays } from "../core/fitlingCore";
import { defaultReminderSettings, fireAt, loadReminderSettings, saveReminderSettings } from "./push";

// The partner's reminders in the browser (web phase 7); reminders.spec.ts hands them to a real server.

const zone = process.env.TZ;

afterEach(() => {
  vi.useRealTimers();
  process.env.TZ = zone;
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

// The rules plan "12:30 on that day" where the user is; the clock decides the moment, also the day the clocks change.
test("aReminderComesAtThatTimeOnThatDay", () => {
  process.env.TZ = "Europe/Amsterdam";
  expect(fireAt("2026-10-24", 12 * 60 + 30).toISOString()).toBe("2026-10-24T10:30:00.000Z");
  // Winter time from 03:00 on 25 October 2026: 12:30 is an hour later in UTC.
  expect(fireAt("2026-10-25", 12 * 60 + 30).toISOString()).toBe("2026-10-25T11:30:00.000Z");
  expect(fireAt("2026-03-29", 18 * 60 + 30).toISOString()).toBe("2026-03-29T16:30:00.000Z");
});

test("theSettingsStayInThisBrowser", () => {
  const stored = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
  });
  expect(loadReminderSettings()).toEqual(defaultReminderSettings);
  saveReminderSettings({ isOn: true, times: [9 * 60, 19 * 60] });
  expect(loadReminderSettings()).toEqual({ isOn: true, times: [9 * 60, 19 * 60] });
  // What another version or a hand left behind is no setting: the defaults, as ReminderSettingsStore on iOS.
  stored.set("fitling.partnerReminders", '{"isOn":"yes","times":[540]}');
  expect(loadReminderSettings()).toEqual(defaultReminderSettings);
  stored.set("fitling.partnerReminders", "not json");
  expect(loadReminderSettings()).toEqual(defaultReminderSettings);
});

/** push.ts as a build with the key has it, in a browser with push (a stand-in) that is or is not online. */
async function pushIn(onLine: boolean) {
  vi.resetModules();
  vi.stubEnv("VITE_VAPID_PUBLIC_KEY", "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8");
  const unsubscribed: boolean[] = [];
  const subscription = {
    endpoint: "https://web.push.apple.com/x",
    options: { applicationServerKey: null },
    toJSON: () => ({ endpoint: "https://web.push.apple.com/x", keys: { p256dh: "p", auth: "a" } }),
    unsubscribe: async () => unsubscribed.push(true),
  };
  const registration = { pushManager: { getSubscription: async () => subscription, subscribe: async () => subscription } };
  vi.stubGlobal("navigator", {
    onLine,
    languages: ["nl-NL"],
    serviceWorker: { ready: Promise.resolve(registration), getRegistration: async () => registration },
  });
  vi.stubGlobal("window", { PushManager: function PushManager() {}, Notification: { permission: "granted" } });
  vi.stubGlobal("Notification", { permission: "granted" });
  const asked: string[] = [];
  const client = {
    rpc: async (name: string) => {
      asked.push(name);
      return { data: "id", error: null };
    },
    from: () => ({ delete: () => ({ eq: async () => (asked.push("delete"), { error: null }) }) }),
  } as unknown as SupabaseClient;
  return { push: await import("./push"), client, asked, unsubscribed };
}

const core = { remindersPlan: () => ({ reminders: [] }) } as unknown as FitlingCore;
const days = {} as PartnerDays;

// Fable's review of phase 7: without a network the plan waits for the next visit; supabase-js would first spend half a
// minute on an expired token.
test("withoutANetworkNothingIsPlanned", async () => {
  const { push, client, asked } = await pushIn(false);
  await push.planReminders(client, core, { settings: { isOn: true, times: [750, 1110] }, name: "Pip", days });
  expect(asked).toEqual([]);
  const online = await pushIn(true);
  await online.push.planReminders(online.client, core, { settings: { isOn: true, times: [750, 1110] }, name: "Pip", days });
  expect(online.asked).toEqual(["save_push_subscription", "replace_push_reminders"]);
});

// Vandaag, the partner tab and every change plan; a plan that started earlier and is slow to arrive must not land after
// a later one: turned off, they stay off (S51, seen in CI run 45796982295 with Chrome 157).
test("theLastPlanIsTheOneThatStays", async () => {
  const { push } = await pushIn(true);
  let release = () => {};
  const slow = new Promise<void>((resolve) => (release = resolve));
  let stored: unknown[] = [];
  const client = {
    rpc: async (name: string, args: { p_reminders?: unknown[] }) => {
      if (name === "save_push_subscription") return { data: "id", error: null };
      // The plan with reminders is the slow one, whichever arrives first.
      if ((args.p_reminders ?? []).length > 0) await slow;
      stored = args.p_reminders ?? [];
      return { data: null, error: null };
    },
  } as unknown as SupabaseClient;
  const planning = {
    remindersPlan: () => ({ reminders: [{ day: "2026-11-26", minutes: 750, messageKey: "creature.message.fit.sweet.1" }] }),
  } as unknown as FitlingCore;
  const on = push.planReminders(client, planning, { settings: { isOn: true, times: [750, 1110] }, name: "Pip", days });
  const off = push.planReminders(client, planning, { settings: { isOn: false, times: [750, 1110] }, name: "Pip", days });
  setTimeout(release, 20);
  await Promise.all([on, off]);
  expect(stored).toEqual([]);
});

const withReminders = {
  remindersPlan: () => ({ reminders: [{ day: "2026-11-26", minutes: 750, messageKey: "creature.message.fit.sweet.1" }] }),
} as unknown as FitlingCore;
const on = { isOn: true, times: [750, 1110] };
const off = { isOn: false, times: [750, 1110] };

/** A server whose first save waits for `first` (or forever); what it last stored and how often. */
function server(first: Promise<void> = new Promise(() => {})) {
  const seen = { stored: undefined as unknown[] | undefined, replaced: 0, saves: 0 };
  const client = {
    rpc: async (name: string, args: { p_reminders?: unknown[] }) => {
      if (name === "save_push_subscription") {
        seen.saves += 1;
        if (seen.saves === 1) await first;
        return { data: "id", error: null };
      }
      seen.replaced += 1;
      seen.stored = args.p_reminders ?? [];
      return { data: null, error: null };
    },
    from: () => ({ delete: () => ({ eq: async () => ({ error: null }) }) }),
  } as unknown as SupabaseClient;
  return { client, seen };
}

// Fable's review of S51: a plan whose connection never answers holds the next one back for half a minute at most, so
// turning them off on a bad connection still reaches the server.
test("aPlanThatHangsDoesNotHoldBackTheNext", async () => {
  vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
  try {
    const { push } = await pushIn(true);
    const { client, seen } = server();
    void push.planReminders(client, withReminders, { settings: on, name: "Pip", days });
    await vi.advanceTimersByTimeAsync(0);
    const later = push.planReminders(client, withReminders, { settings: off, name: "Pip", days });
    await vi.advanceTimersByTimeAsync(30_000);
    await later;
    expect(seen.stored).toEqual([]);
  } finally {
    vi.useRealTimers();
  }
});

// And when that plan answers after all, it was overtaken: it leaves the server alone.
test("aPlanThatWasOvertakenLeavesTheServerAlone", async () => {
  vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
  try {
    const { push } = await pushIn(true);
    let answer = () => {};
    const { client, seen } = server(new Promise<void>((resolve) => (answer = resolve)));
    const earlier = push.planReminders(client, withReminders, { settings: on, name: "Pip", days });
    await vi.advanceTimersByTimeAsync(0);
    const later = push.planReminders(client, withReminders, { settings: off, name: "Pip", days });
    await vi.advanceTimersByTimeAsync(30_000);
    await later;
    answer();
    await earlier;
    expect(seen.stored).toEqual([]);
    expect(seen.replaced).toBe(1);
  } finally {
    vi.useRealTimers();
  }
});

// Signing out while plans wait: none of them reaches the server afterwards, so no reminder carries the name of a
// partner whose owner is gone.
test("signingOutStopsThePlansThatWait", async () => {
  const { push } = await pushIn(true);
  let answer = () => {};
  const { client, seen } = server(new Promise<void>((resolve) => (answer = resolve)));
  const first = push.planReminders(client, withReminders, { settings: on, name: "Pip", days });
  const second = push.planReminders(client, withReminders, { settings: on, name: "Pip", days });
  await new Promise((resolve) => setTimeout(resolve, 0));
  await push.forgetPush(client);
  answer();
  await Promise.all([first, second]);
  expect(seen.replaced).toBe(0);
});

// Signing out without a network still stops the reminders here; the server is not asked.
test("withoutANetworkSigningOutStillStopsThem", async () => {
  const { push, client, asked, unsubscribed } = await pushIn(false);
  await push.forgetPush(client);
  expect(asked).toEqual([]);
  expect(unsubscribed).toEqual([true]);
});
