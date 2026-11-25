import type { SupabaseClient } from "@supabase/supabase-js";
import type { AuthService } from "./auth";
import { forgetOffline } from "./offline";
import { removeAllPhotos } from "./photos";
import { forgetPush } from "./push";

/**
 * Deletes the account and everything in it through the Edge Function delete-account, then ends the session, as
 * AccountViewModel.deleteAccount does on iOS. The function checks the user's own token.
 */
export async function deleteAccount(client: SupabaseClient, auth: AuthService): Promise<void> {
  const { error } = await client.functions.invoke("delete-account", { method: "POST" });
  if (error) throw new Error("error.server");
  // The server took the reminders with the account; this browser stops listening for them.
  await forgetPush(client).catch(() => undefined);
  await auth.signOut().catch(() => undefined);
  forgetOffline();
  await removeAllPhotos();
}
