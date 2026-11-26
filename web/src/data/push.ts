import type { SupabaseClient } from "@supabase/supabase-js";
import type { FitlingCore, IsoDay, PartnerDays, ReminderSettings } from "../core/fitlingCore";
import { t } from "../i18n";
import { failure } from "./failure";
import { noNetwork } from "./offline";

/**
 * The partner's reminders on the web (phase 7), as PartnerViewModel plans them on the iPhone: the browser plans today
 * and tomorrow with ReminderPlanner, and the server sends each one with Web Push when its time has come
 * (send-reminders, docs/web-push.md). The settings stay in this browser, as on the iPhone they stay on the device.
 */

/** The public half of the VAPID key pair (docs/web-push.md); without it the web app has no reminders. */
const vapidPublicKey = (import.meta.env.VITE_VAPID_PUBLIC_KEY as string | undefined) ?? "";

/**
 * "off": this build has no reminders. "homeScreen": this browser cannot receive them, as Safari on an iPhone outside
 * the home screen. "ready": they can be turned on.
 */
export type PushSupport = "off" | "homeScreen" | "ready";

export function pushSupport(): PushSupport {
  if (vapidPublicKey === "") return "off";
  if (!("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) return "homeScreen";
  return "ready";
}

/** Where the settings are kept in this browser (ReminderSettingsStore.key on iOS). */
const settingsKey = "fitling.partnerReminders";

/** Off, at lunch and dinner (ReminderSettings on iOS). */
export const defaultReminderSettings: ReminderSettings = { isOn: false, times: [12 * 60 + 30, 18 * 60 + 30] };

export function loadReminderSettings(): ReminderSettings {
  try {
    const stored = JSON.parse(localStorage.getItem(settingsKey) ?? "null") as Partial<ReminderSettings> | null;
    const times = stored?.times;
    if (typeof stored?.isOn === "boolean" && Array.isArray(times) && times.length === 2 && times.every(Number.isInteger)) {
      return { isOn: stored.isOn, times };
    }
  } catch {
    // Nothing usable kept: the defaults.
  }
  return defaultReminderSettings;
}

export function saveReminderSettings(settings: ReminderSettings): void {
  try {
    localStorage.setItem(settingsKey, JSON.stringify(settings));
  } catch {
    // A browser that keeps nothing asks again next time.
  }
}

/** The browser said no to notifications for Fitling: only its own settings can change that. */
export function notificationsRefused(): boolean {
  return pushSupport() === "ready" && Notification.permission === "denied";
}

function fromBase64url(text: string): Uint8Array<ArrayBuffer> {
  const plain = text.replaceAll("-", "+").replaceAll("_", "/");
  const binary = atob(plain + "=".repeat((4 - (plain.length % 4)) % 4));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function sameKey(key: ArrayBuffer | null | undefined, expected: Uint8Array): boolean {
  if (!key) return false;
  const bytes = new Uint8Array(key);
  return bytes.length === expected.length && bytes.every((byte, index) => byte === expected[index]);
}

/** This browser's subscription with the push service; a new one when it has none, or one for another key. */
async function subscription(): Promise<PushSubscription> {
  const registration = await navigator.serviceWorker.ready;
  const key = fromBase64url(vapidPublicKey);
  const current = await registration.pushManager.getSubscription();
  if (current && sameKey(current.options.applicationServerKey, key)) return current;
  await current?.unsubscribe();
  return registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
}

/**
 * Turning reminders on, from a tap: the browser asks for permission once, afterwards it answers without asking again;
 * then this browser subscribes with its push service (PartnerViewModel.setRemindersOn). "refused" when the user or the
 * browser says no; "failed" when subscribing did not work, for example without a connection.
 */
export async function turnOn(): Promise<"on" | "refused" | "failed"> {
  if (pushSupport() !== "ready") return "refused";
  // The question first, straight from the tap: Safari asks only while the tap is being handled.
  const answer = Notification.permission === "default" ? Notification.requestPermission() : Promise.resolve(Notification.permission);
  if ((await answer) !== "granted") return "refused";
  if (noNetwork()) return "failed";
  try {
    await subscription();
  } catch {
    return "failed";
  }
  return "on";
}

/** The moment `minutes` after midnight on `day` where the user is, also on a day the clocks change. */
export function fireAt(day: IsoDay, minutes: number): Date {
  const [year, month, date] = day.split("-").map(Number);
  return new Date(year, month - 1, date, Math.floor(minutes / 60), minutes % 60);
}

/** What was last handed to the server, so reading Vandaag again does not send the same plan again. */
let handed: { endpoint: string; id: string; plan: string } | undefined;

/** The plans asked for so far, one after the other. */
let planning: Promise<void> = Promise.resolve();

/**
 * Plans the reminders of today and tomorrow and hands them to the server, replacing what it had for this browser
 * (PartnerViewModel.planReminders). Turned off, the plan is empty. Without permission nothing is subscribed.
 * Vandaag, the partner tab and every change ask for a plan: they run one at a time, in the order asked, so a plan
 * that started earlier never lands after a later one (turned off, they stay off).
 */
export function planReminders(
  client: SupabaseClient,
  core: FitlingCore,
  plan: { settings: ReminderSettings; name: string; days: PartnerDays },
  now = new Date(),
): Promise<void> {
  const next = planning.then(() => planNow(client, core, plan, now));
  planning = next.catch(() => undefined);
  return next;
}

async function planNow(
  client: SupabaseClient,
  core: FitlingCore,
  plan: { settings: ReminderSettings; name: string; days: PartnerDays },
  now: Date,
): Promise<void> {
  // Without a network the plan waits for the next visit: supabase-js would first spend half a minute on the token.
  if (pushSupport() !== "ready" || Notification.permission !== "granted" || noNetwork()) return;
  // Turned off, a browser that never subscribed stays that way; one that did gets an empty plan.
  const current = plan.settings.isOn ? await subscription() : await (await navigator.serviceWorker.ready).pushManager.getSubscription();
  if (!current) return;
  const browser = current.toJSON();
  const endpoint = browser.endpoint ?? "";
  let id = handed?.endpoint === endpoint ? handed.id : undefined;
  if (!id) {
    const { data, error } = await client.rpc("save_push_subscription", {
      p_endpoint: endpoint,
      p_p256dh: browser.keys?.p256dh ?? "",
      p_auth: browser.keys?.auth ?? "",
    });
    if (error) throw failure(error);
    id = data as string;
  }
  const { reminders } = plan.settings.isOn
    ? core.remindersPlan({ settings: plan.settings, minutesNow: now.getHours() * 60 + now.getMinutes(), days: plan.days })
    : { reminders: [] };
  const rows = reminders.map((reminder) => ({
    fire_at: fireAt(reminder.day, reminder.minutes).toISOString(),
    title: plan.name,
    body: t(reminder.messageKey),
  }));
  const planned = JSON.stringify(rows);
  if (handed?.id === id && handed.plan === planned) return;
  const { error } = await client.rpc("replace_push_reminders", { p_subscription: id, p_reminders: rows });
  if (error) {
    handed = undefined;
    throw failure(error);
  }
  handed = { endpoint, id, plan: planned };
}

async function currentSubscription(): Promise<PushSubscription | null | undefined> {
  if (pushSupport() !== "ready") return undefined;
  return (await navigator.serviceWorker.getRegistration())?.pushManager.getSubscription();
}

/**
 * Signing out or deleting the account: this browser's subscription goes, and with it the reminders, which carry the
 * partner's name and mood (RootViewModel on iOS empties them too). Needs the session, so it runs before signing out.
 */
export async function forgetPush(client: SupabaseClient): Promise<void> {
  handed = undefined;
  const current = await currentSubscription();
  if (!current) return;
  if (!noNetwork()) await client.from("push_subscriptions").delete().eq("endpoint", current.endpoint);
  await current.unsubscribe();
}

/**
 * Nobody signed in, also after a session that ended by itself: this browser stops listening. The push service then
 * answers 410 to the server, and send-reminders removes the subscription with its reminders.
 */
export async function stopPushHere(): Promise<void> {
  handed = undefined;
  await (await currentSubscription())?.unsubscribe();
}
