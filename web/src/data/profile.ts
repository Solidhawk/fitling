import type { SupabaseClient } from "@supabase/supabase-js";
import type { Lookup } from "../screens/route";

/** Whether the server has a profile and a partner for this user; any failure is "failed", never "none". */
export async function lookUp(client: SupabaseClient, userID: string): Promise<Lookup> {
  const [profile, creature] = await Promise.all([
    client.from("profiles").select("id").eq("id", userID).maybeSingle(),
    client.from("creatures").select("user_id").eq("user_id", userID).maybeSingle(),
  ]);
  if (profile.error || creature.error) return { kind: "failed" };
  return { kind: "loaded", hasProfile: profile.data !== null, hasCreature: creature.data !== null };
}
