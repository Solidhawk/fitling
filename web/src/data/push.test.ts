import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, expect, test, vi } from "vitest";
import type { FitlingCore, PartnerDays } from "../core/fitlingCore";
import { defaultReminderSettings, fireAt, loadReminderSettings, saveReminderSettings } from "./push";

// The partner's reminders in the browser (web phase 7); reminders.spec.ts hands them to a real server.

const zone = process.env.TZ;

afterEach(() => {
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
  vi.stubGlobal("navigator", { onLine, serviceWorker: { ready: Promise.resolve(registration), getRegistration: async () => registration } });
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

// Signing out without a network still stops the reminders here; the server is not asked.
test("withoutANetworkSigningOutStillStopsThem", async () => {
  const { push, client, asked, unsubscribed } = await pushIn(false);
  await push.forgetPush(client);
  expect(asked).toEqual([]);
  expect(unsubscribed).toEqual([true]);
});
