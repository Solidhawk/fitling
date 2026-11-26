// Makes the VAPID key pair for send-reminders (docs/web-push.md). Run it once, on your own computer:
//   deno run supabase/functions/send-reminders/vapid-keys.ts
// The private key goes only into the secrets of the Supabase project; the public key goes there too, and into the
// GitHub variable VAPID_PUBLIC_KEY of the web build.
import { newVapidKeys } from './webpush.ts';

const keys = await newVapidKeys();
console.log(`VAPID_PUBLIC_KEY=${keys.publicKey}`);
console.log(`VAPID_PRIVATE_KEY=${keys.privateKey}`);
