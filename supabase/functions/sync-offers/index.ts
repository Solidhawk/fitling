import { createClient } from '@supabase/supabase-js';
import { misconfigured, readConfig } from '../delete-account/handler.ts';
import { handle } from './handler.ts';
import type { OfferProvider } from './provider.ts';
import { TestDataProvider } from './testdata.ts';

// The registered sources. Until RISKS R-13 is settled there is only test data.
const providers: OfferProvider[] = [new TestDataProvider(() => new Date())];

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
