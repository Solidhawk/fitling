import { createClient } from '@supabase/supabase-js';
import { misconfigured, readConfig } from '../delete-account/handler.ts';
import { handle } from './handler.ts';
import { prijsProfeetProviders } from './prijsprofeet.ts';

// The source of the offers: PrijsProfeet, one provider per Dutch chain (RISKS R-13). The optional
// secret PRIJSPROFEET_API_KEY raises their limit from 30 to 150 requests a minute.
const providers = prijsProfeetProviders({
  fetch,
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  userAgent: 'Fitling/1.0',
  apiKey: Deno.env.get('PRIJSPROFEET_API_KEY') || undefined,
});

const config = readConfig((name) => Deno.env.get(name));

if ('missing' in config) {
  console.error(`misconfigured: missing ${config.missing.join(', ')}`);
  Deno.serve(() => misconfigured());
} else {
  const admin = createClient(config.url, config.secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  Deno.serve((req) =>
    handle(req, config.secretKey, providers, {
      async upsertSupermarket(id, name) {
        const { error } = await admin.from('supermarkets').upsert({ id, name, updated_at: new Date().toISOString() });
        if (error) throw error;
      },
      async upsertOffers(rows) {
        const synced = rows.map((row) => ({ ...row, synced_at: new Date().toISOString() }));
        const { error } = await admin.from('offers').upsert(synced, {
          onConflict: 'supermarket_id,external_id,valid_from',
        });
        if (error) throw error;
      },
      async removeExpired(before) {
        const { count, error } = await admin.from('offers').delete({ count: 'exact' }).lt('valid_to', before);
        if (error) throw error;
        return count ?? 0;
      },
      now: () => new Date(),
      log(message) {
        console.error(message);
      },
    })
  );
}
