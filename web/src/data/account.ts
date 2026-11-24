import type { SupabaseClient } from "@supabase/supabase-js";
import type { AuthService } from "./auth";
import { removeAllPhotos } from "./photos";

/**
 * Deletes the account and everything in it through the Edge Function delete-account, then ends the session, as
 * AccountViewModel.deleteAccount does on iOS. The function checks the user's own token.
 */
export async function deleteAccount(client: SupabaseClient, auth: AuthService): Promise<void> {
  const { error } = await client.functions.invoke("delete-account", { method: "POST" });
  if (error) throw new Error("error.server");
  await auth.signOut().catch(() => undefined);
  await removeAllPhotos();
}
