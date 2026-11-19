import { createClient } from '@supabase/supabase-js';
import { readConfig } from '../delete-account/handler.ts';
import { handle, type StoredProduct } from './handler.ts';
import { fetchOffProduct } from './openfoodfacts.ts';

/** Calls per user per hour (ARCHITECTURE §4). */
const hourlyLimit = 60;

const config = readConfig((name) => Deno.env.get(name));
// Open Food Facts asks for an app name and a contact address; the address is a secret of the
// project, not something in the code.
const userAgent = Deno.env.get('OFF_USER_AGENT') ?? 'Fitling/1.0';

if ('missing' in config) {
  console.error(`misconfigured: missing ${config.missing.join(', ')}`);
  Deno.serve(() => Response.json({ error: 'misconfigured' }, { status: 500 }));
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
          bucket: `lookup:${userID}`,
          max_calls: hourlyLimit,
        });
        if (error) throw error;
        return data === true;
      },
      async findShared(gtin) {
        const { data, error } = await admin.from('products').select().eq('gtin', gtin).is('owner_id', null)
          .maybeSingle();
        if (error) throw error;
        return data as StoredProduct | null;
      },
      fetchOff(gtin) {
        return fetchOffProduct(gtin, {
          fetch,
          sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
          userAgent,
        });
      },
      async storeShared(row) {
        const { data, error } = await admin.rpc('store_shared_product', { product: row });
        if (error) throw error;
        return data as StoredProduct;
      },
      now: () => new Date(),
      log(message) {
        console.error(message);
      },
    })
  );
}
