import { createClient } from "@supabase/supabase-js";

// The publishable key is public by design (CLAUDE.md); the secret key never comes near the web app.
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;

if (!url || !key) {
  throw new Error("VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY are needed to build the web app");
}

export const supabase = createClient(url, key, { auth: { persistSession: true, detectSessionInUrl: true } });
