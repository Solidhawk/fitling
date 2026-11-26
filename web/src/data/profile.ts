import type { SupabaseClient } from "@supabase/supabase-js";
import type { Lookup } from "../screens/route";
import { failure } from "./failure";
import { kept } from "./offline";

/**
 * Whether the server has a profile and a partner for this user; any failure is "failed", never "none". Without a
 * connection the last answer counts, so the app opens on Vandaag as on the iPhone.
 */
export async function lookUp(client: SupabaseClient, userID: string): Promise<Lookup> {
  try {
    return await kept("lookup", async (): Promise<Lookup> => {
      const [profile, creature] = await Promise.all([
        client.from("profiles").select("id").eq("id", userID).maybeSingle(),
        client.from("creatures").select("user_id").eq("user_id", userID).maybeSingle(),
      ]);
      if (profile.error || creature.error) throw failure(profile.error ?? creature.error);
      return { kind: "loaded", hasProfile: profile.data !== null, hasCreature: creature.data !== null };
    });
  } catch {
    return { kind: "failed" };
  }
}
