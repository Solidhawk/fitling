import { encrypt, vapidAuthorization, type VapidKeys } from './webpush.ts';

/** A reminder whose time has come, with the browser it goes to. */
export type Due = {
  id: string;
  subscriptionID: string;
  fireAt: string;
  title: string;
  body: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  /** Until when this call holds it (claim_push_reminders): releasing frees only this call's own claim. */
  claimedUntil: string;
};

export type Deps = {
  /**
   * Reminders whose time has come that no other call is sending, oldest first, at most `limit`; claimed for this call
   * (claim_push_reminders in web-push.sql).
   */
  claim(limit: number): Promise<Due[]>;
  removeReminders(ids: string[]): Promise<void>;
  /** Claimed reminders that must wait go back for the next minute, as long as `claimedUntil` is still their claim. */
  release(ids: string[], claimedUntil: string): Promise<void>;
  /** Removes a browser's subscription, and with it its reminders (on delete cascade). */
  removeSubscription(id: string): Promise<void>;
  send(request: Request): Promise<Response>;
  now(): Date;
  log(message: string): void;
};

/** Reminders per call; the scheduler calls every minute, so a backlog clears within minutes. */
const batch = 200;
/**
 * A reminder more than this late is not sent: a lunch reminder after an outage would come at the wrong moment, and
 * one that falls past 21:00 would break the quiet hours (ReminderSettings).
 */
const lateMs = 30 * 60 * 1000;
/**
 * A call stops sending after this long and lets the rest go: its claim lasts five minutes, and a push service that does
 * not answer takes fifteen seconds. Past the claim, the next minute's call would send the same reminder again.
 */
const sendingMs = 4 * 60 * 1000;

/**
 * The push services of Safari, Chrome, Firefox and Edge. Only these are called: an endpoint is whatever a browser
 * sent, and the function must never be a way to reach other hosts.
 */
export function knownPushService(endpoint: string): boolean {
  let url: URL;
  try {
    url = new URL(endpoint);
  } catch {
    return false;
  }
  if (url.protocol !== 'https:' || url.port !== '' || url.username !== '' || url.password !== '') return false;
  const host = url.hostname;
  return ['web.push.apple.com', 'fcm.googleapis.com', 'updates.push.services.mozilla.com'].includes(host) ||
    host.endsWith('.notify.windows.com');
}

type Outcome = 'sent' | 'dropped' | 'waiting';

async function deliver(reminder: Due, vapid: VapidKeys & { subject: string }, deps: Deps): Promise<Outcome> {
  const now = deps.now();
  if (!knownPushService(reminder.endpoint)) {
    await deps.removeSubscription(reminder.subscriptionID);
    return 'dropped';
  }
  if (now.getTime() - Date.parse(reminder.fireAt) > lateMs) {
    await deps.removeReminders([reminder.id]);
    return 'dropped';
  }
  // The push service keeps it for a phone that is off only until it would be too late: never into the quiet hours.
  const ttlSeconds = Math.max(1, Math.floor((lateMs - (now.getTime() - Date.parse(reminder.fireAt))) / 1000));
  let request: Request;
  try {
    const message = new TextEncoder().encode(JSON.stringify({ title: reminder.title, body: reminder.body }));
    const body = await encrypt(message, reminder.p256dh, reminder.auth);
    request = new Request(reminder.endpoint, {
      method: 'POST',
      headers: {
        Authorization: await vapidAuthorization(reminder.endpoint, vapid, vapid.subject, now),
        'Content-Encoding': 'aes128gcm',
        'Content-Type': 'application/octet-stream',
        TTL: String(ttlSeconds),
        Urgency: 'normal',
      },
      body,
      // An endpoint is whatever a browser sent: a redirect is not followed past the allow-list, and a push service
      // that does not answer does not hold up the others.
      redirect: 'manual',
      signal: AbortSignal.timeout(15_000),
    });
  } catch (error) {
    deps.log(`send-reminders: cannot encrypt for subscription ${reminder.subscriptionID}: ${String(error)}`);
    await deps.removeReminders([reminder.id]);
    return 'dropped';
  }
  const response = await deps.send(request);
  await response.body?.cancel();
  // RFC 8030: 201 Created. Gone or unknown: the browser unsubscribed. Too many or a server problem: next minute.
  if (response.ok) {
    await removeSent(reminder, deps);
    return 'sent';
  }
  if (response.status === 404 || response.status === 410) {
    await deps.removeSubscription(reminder.subscriptionID);
    return 'dropped';
  }
  if (response.status === 429 || response.status >= 500) return 'waiting';
  deps.log(`send-reminders: push service answered ${response.status} for subscription ${reminder.subscriptionID}`);
  await deps.removeReminders([reminder.id]);
  return 'dropped';
}

/**
 * Sent: the row goes. Asked twice, because a sent reminder that stayed would go out once more when its claim runs out.
 */
async function removeSent(reminder: Due, deps: Deps) {
  try {
    await deps.removeReminders([reminder.id]);
  } catch {
    try {
      await deps.removeReminders([reminder.id]);
    } catch (error) {
      deps.log(`send-reminders: cannot remove sent reminder ${reminder.id}: ${String(error)}`);
    }
  }
}

/**
 * Sends the reminders whose time has come. Runs only when called with the project's secret key, by the scheduler
 * (send-reminders-cron.sql), never by the app. One browser that fails does not stop the others.
 */
export async function handle(
  req: Request,
  secretKey: string,
  vapid: VapidKeys & { subject: string },
  deps: Deps,
): Promise<Response> {
  if (req.headers.get('Authorization') !== `Bearer ${secretKey}`) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }
  const counts: Record<Outcome, number> = { sent: 0, dropped: 0, waiting: 0 };
  const waiting: Due[] = [];
  const started = deps.now().getTime();
  const claimed = await deps.claim(batch);
  for (const [index, reminder] of claimed.entries()) {
    if (deps.now().getTime() - started > sendingMs) {
      const rest = claimed.slice(index);
      waiting.push(...rest);
      counts.waiting += rest.length;
      break;
    }
    let outcome: Outcome;
    try {
      outcome = await deliver(reminder, vapid, deps);
    } catch (error) {
      deps.log(`send-reminders: subscription ${reminder.subscriptionID} failed: ${String(error)}`);
      outcome = 'waiting';
    }
    counts[outcome] += 1;
    if (outcome === 'waiting') waiting.push(reminder);
  }
  // Per claim: one call claims all its reminders at once, so this is one request.
  for (const claimedUntil of new Set(waiting.map((reminder) => reminder.claimedUntil))) {
    const ids = waiting.filter((reminder) => reminder.claimedUntil === claimedUntil).map((reminder) => reminder.id);
    try {
      await deps.release(ids, claimedUntil);
    } catch (error) {
      // The claim runs out by itself after five minutes.
      deps.log(`send-reminders: cannot release ${ids.length} reminders: ${String(error)}`);
    }
  }
  return Response.json(counts);
}
