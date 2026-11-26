import { createClient } from "@supabase/supabase-js";
import { expect, type Page } from "./fixtures";
import { admin, createUser, localDay, nl, password, signIn } from "./users";

/** A supermarket of its own for one test, with offers valid from today for `days` days, freshly fetched. */
export async function shopWithOffers(name: string, offers: { title: string; cents: number }[], days = 3): Promise<string> {
  const id = `e2e_${crypto.randomUUID().replace(/-/g, "").slice(0, 12)}`;
  const shop = await admin.from("supermarkets").insert({ id, name });
  if (shop.error) throw shop.error;
  const until = new Date();
  until.setDate(until.getDate() + days);
  const stored = await admin.from("offers").insert(
    offers.map((offer) => ({
      supermarket_id: id,
      external_id: crypto.randomUUID(),
      title: offer.title,
      price_cents: offer.cents,
      valid_from: localDay(),
      valid_to: localDay(until),
    })),
  );
  if (stored.error) throw stored.error;
  return id;
}

/**
 * Someone else's list, with an item, and a code to join it, made as that user does in the app (signed in with the
 * publishable key, through the same RPC).
 */
export async function sharedList(listName: string, ownerName: string, item: string): Promise<{ code: string; listID: string }> {
  const owner = await createUser({ profile: true });
  const client = createClient(process.env.VITE_SUPABASE_URL ?? "", process.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? "", { auth: { persistSession: false } });
  const session = await client.auth.signInWithPassword({ email: owner.email, password });
  if (session.error) throw session.error;
  const listID = crypto.randomUUID();
  const now = new Date().toISOString();
  const list = await client.from("shopping_lists").insert({ id: listID, name: listName, created_by: owner.id, updated_at: now });
  if (list.error) throw list.error;
  const member = await client.from("shopping_list_members").insert({ list_id: listID, user_id: owner.id, role: "owner", display_name: ownerName });
  if (member.error) throw member.error;
  const items = await client
    .from("shopping_items")
    .insert({ id: crypto.randomUUID(), list_id: listID, name: item, aisle: "other", source: "manual", updated_by: owner.id, updated_at: now });
  if (items.error) throw items.error;
  const code = await client.rpc("create_shopping_list_invite", { list: listID });
  if (code.error) throw code.error;
  return { code: code.data as string, listID };
}

/** Signed in with a profile and a partner, on the shopping list (Menu, then Boodschappen). */
export async function openShopping(page: Page, prepare?: (userID: string) => Promise<void>) {
  const user = await createUser({ profile: true, creature: true });
  await prepare?.(user.id);
  await signIn(page, user.email);
  await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
  await page.getByRole("tab", { name: nl("menu.title") }).click();
  await page.getByTestId("menu.shopping").click();
  await expect(page.getByTestId("shopping.add.field")).toBeVisible({ timeout: 15_000 });
  return user;
}
