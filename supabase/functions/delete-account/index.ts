import { createClient } from '@supabase/supabase-js';
import { revokeAppleToken } from './apple.ts';
import { handle, misconfigured, readConfig } from './handler.ts';

const config = readConfig((name) => Deno.env.get(name));

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing secret ${name}`);
  return value;
}

if ('missing' in config) {
  // Said once at start, so the log shows what to set instead of a failing request per user.
  console.error(`misconfigured: missing ${config.missing.join(', ')}`);
  Deno.serve(() => misconfigured());
} else {
  const admin = createClient(config.url, config.secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  Deno.serve((req) =>
    handle(req, {
      async getUser(token) {
        const { data, error } = await admin.auth.getUser(token);
        if (error || !data.user) return null;
        const providers = data.user.app_metadata?.providers;
        return { id: data.user.id, providers: Array.isArray(providers) ? providers : [] };
      },
      async deleteUser(id) {
        const { error } = await admin.auth.admin.deleteUser(id);
        if (error) throw error;
      },
      revokeApple(code) {
        return revokeAppleToken(
          code,
          {
            teamId: requiredEnv('APPLE_TEAM_ID'),
            keyId: requiredEnv('APPLE_KEY_ID'),
            clientId: requiredEnv('APPLE_CLIENT_ID'),
            privateKeyPem: requiredEnv('APPLE_PRIVATE_KEY'),
          },
          fetch,
          Math.floor(Date.now() / 1000),
        );
      },
      log(message) {
        console.error(message);
      },
    })
  );
}
