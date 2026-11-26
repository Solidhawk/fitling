import { createClient } from '@supabase/supabase-js';
import { misconfigured, readConfig } from '../delete-account/handler.ts';
import { type Due, handle } from './handler.ts';

/** A row of claim_push_reminders (web-push.sql). */
type Claimed = {
  id: string;
  subscription_id: string;
  fire_at: string;
  title: string;
  body: string;
  endpoint: string;
  p256dh: string;
  auth: string;
};

// The partner's reminders for the web version on the home screen (web phase 7), sent every minute by pg_cron
// (send-reminders-cron.sql). The VAPID key pair is a secret of the project (docs/web-push.md); its public half is
// also the GitHub variable VITE_VAPID_PUBLIC_KEY of the web build.
const config = readConfig((name) => Deno.env.get(name));
const vapidPublic = Deno.env.get('VAPID_PUBLIC_KEY') ?? '';
const vapidPrivate = Deno.env.get('VAPID_PRIVATE_KEY') ?? '';
/** How a push service can reach the sender (RFC 8292): the web app's own address. */
const subject = 'https://solidhawk.github.io/fitling/';

if ('missing' in config || vapidPublic === '' || vapidPrivate === '') {
  const missing = [
    ...('missing' in config ? config.missing : []),
    ...(vapidPublic === '' ? ['VAPID_PUBLIC_KEY'] : []),
    ...(vapidPrivate === '' ? ['VAPID_PRIVATE_KEY'] : []),
  ];
  console.error(`misconfigured: missing ${missing.join(', ')}`);
  Deno.serve(() => misconfigured());
} else {
  const admin = createClient(config.url, config.secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  Deno.serve((req) =>
    handle(req, config.secretKey, { publicKey: vapidPublic, privateKey: vapidPrivate, subject }, {
      async claim(limit) {
        const { data, error } = await admin.rpc('claim_push_reminders', { p_limit: limit });
        if (error) throw error;
        return ((data ?? []) as Claimed[]).map((row): Due => ({
          id: row.id,
          subscriptionID: row.subscription_id,
          fireAt: row.fire_at,
          title: row.title,
          body: row.body,
          endpoint: row.endpoint,
          p256dh: row.p256dh,
          auth: row.auth,
        }));
      },
      async removeReminders(ids) {
        const { error } = await admin.from('push_reminders').delete().in('id', ids);
        if (error) throw error;
      },
      async release(ids) {
        const { error } = await admin.from('push_reminders').update({ claimed_until: null }).in('id', ids);
        if (error) throw error;
      },
      async removeSubscription(id) {
        const { error } = await admin.from('push_subscriptions').delete().eq('id', id);
        if (error) throw error;
      },
      send: (request) => fetch(request),
      now: () => new Date(),
      log(message) {
        console.error(message);
      },
    })
  );
}
