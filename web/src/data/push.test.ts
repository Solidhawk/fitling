import { afterEach, expect, test, vi } from "vitest";
import { defaultReminderSettings, fireAt, loadReminderSettings, saveReminderSettings } from "./push";

// The partner's reminders in the browser (web phase 7); reminders.spec.ts hands them to a real server.

const zone = process.env.TZ;

afterEach(() => {
  process.env.TZ = zone;
  vi.unstubAllGlobals();
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
