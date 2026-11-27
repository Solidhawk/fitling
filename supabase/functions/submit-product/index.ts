import { createClient } from '@supabase/supabase-js';
import { misconfigured, readConfig } from '../delete-account/handler.ts';
import { handle } from './handler.ts';

/** Products a user may share per hour: enough for a cupboard, not for a script. */
const hourlyLimit = 20;

const config = readConfig((name) => Deno.env.get(name));

if ('missing' in config) {
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
        return error || !data.user ? null : { id: data.user.id };
      },
      async consumeRateLimit(userID) {
        const { data, error } = await admin.rpc('consume_rate_limit', {
          bucket: `submit:${userID}`,
          max_calls: hourlyLimit,
        });
        if (error) throw error;
        return data === true;
      },
      async submit(userID, payload, row) {
        const { data, error } = await admin.rpc('submit_shared_product', {
          p_user: userID,
          p_payload: payload,
          p_product: row,
        });
        if (error) throw error;
        const result = (data as { shared_id: string; made_new: boolean }[] | null)?.[0];
        if (!result?.shared_id) throw new Error('submit_shared_product gave no row');
        return { productID: result.shared_id, created: result.made_new };
      },
      log(message) {
        console.error(message);
      },
    })
  );
}
