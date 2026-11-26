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
      async storeSubmission(userID, gtin, payload) {
        const { data, error } = await admin.from('product_submissions').insert({ user_id: userID, gtin, payload })
          .select('id')
          .single();
        if (error) throw error;
        return data.id as string;
      },
      async findShared(gtin) {
        const { data, error } = await admin.from('products').select('id').eq('gtin', gtin).is('owner_id', null)
          .is('deleted_at', null).maybeSingle();
        if (error) throw error;
        return data as { id: string } | null;
      },
      async insertShared(row) {
        const { data, error } = await admin.from('products').insert({ ...row, updated_at: new Date().toISOString() })
          .select('id').single();
        // Another user's share for this barcode was just ahead: the unique index on shared barcodes.
        if (error?.code === '23505') return null;
        if (error) throw error;
        return data.id as string;
      },
      async markAccepted(submissionID, productID) {
        const { error } = await admin.from('product_submissions').update({ status: 'accepted', product_id: productID })
          .eq('id', submissionID);
        if (error) throw error;
      },
    })
  );
}
