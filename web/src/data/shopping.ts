import type { SupabaseClient } from "@supabase/supabase-js";
import type { IsoDay, Localized, NewShoppingItem, OfferRow, RecipeIngredientRow, ShoppingInput, ShoppingItemRow } from "../core/fitlingCore";
import { failure } from "./failure";
import { allRows, type Row } from "./pages";
import { limitedText } from "../text";

export interface ShoppingList {
  id: string;
  name: string;
}

/** Someone on the list (shopping_list_members): the name the others see. */
export interface ListMember {
  userID: string;
  role: "owner" | "member";
  displayName: string;
}

/** The list and everything ShoppingBook reads for it, plus its members. */
export type ShoppingRows = Omit<ShoppingInput, "today" | "confirmedOfferIDs"> & {
  list: ShoppingList;
  members: ListMember[];
};

type Page = PromiseLike<{ data: Row[] | null; error: { message: string } | null }>;

/** How old an offer may be: PrijsProfeet's terms allow a price shown as current only when at most a day old, and
 * the job runs nightly (SupabaseOfferSource on iOS). */
const offerLifetimeMs = 26 * 3_600_000;

const optional = <T>(value: unknown) => (value === null || value === undefined ? undefined : (value as T));

async function write(work: PromiseLike<{ error: { message: string } | null }>) {
  const { error } = await work;
  if (error) throw failure(error);
}

/**
 * The user's list: `preferred` while the user can still see it (the list they joined, remembered on this device), else
 * the first by name (ShoppingStore.ensureList), or a new one with the user as its owner. A list the user made
 * elsewhere without becoming its member yet (offline on the iPhone) gets its owner here too.
 */
export async function ensureList(
  client: SupabaseClient,
  userID: string,
  name: string,
  ownerName: string,
  now: Date,
  preferred?: string,
): Promise<ShoppingList> {
  let query = client.from("shopping_lists").select("id, name, created_by").is("deleted_at", null);
  if (preferred) {
    const kept = await query.eq("id", preferred).limit(1);
    if (kept.error) throw failure(kept.error);
    const row = (kept.data as Row[])[0];
    if (row) return { id: row.id as string, name: row.name as string };
    query = client.from("shopping_lists").select("id, name, created_by").is("deleted_at", null);
  }
  const found = await query.order("name").order("id").limit(1);
  if (found.error) throw failure(found.error);
  const first = (found.data as Row[])[0];
  if (first) {
    if (first.created_by === userID) await addOwner(client, userID, first.id as string, ownerName);
    return { id: first.id as string, name: first.name as string };
  }
  const list = { id: crypto.randomUUID(), name: limitedText(name, 60) };
  await write(client.from("shopping_lists").insert({ ...list, created_by: userID, updated_at: now.toISOString() }));
  await addOwner(client, userID, list.id, ownerName);
  return list;
}

/**
 * The maker of a list as its owner, once (SupabaseListSharing.addOwner). A plain insert, and "already a member" (23505)
 * is fine: an upsert (ON CONFLICT) also needs the read policy to let the new row through, and that policy asks for the
 * membership this row is only now giving.
 */
async function addOwner(client: SupabaseClient, userID: string, listID: string, ownerName: string) {
  const { error } = await client
    .from("shopping_list_members")
    .insert({ list_id: listID, user_id: userID, role: "owner", display_name: limitedText(ownerName, 40) });
  if (error && error.code !== "23505") throw failure(error);
}

export type ListRows = Pick<ShoppingRows, "list" | "items" | "members">;
export type OfferRows = Pick<ShoppingRows, "supermarkets" | "favoriteSupermarketIDs" | "offers">;

/** The list, its items and its members in the order they joined: what changes when someone ticks or adds an item. */
export async function loadList(client: SupabaseClient, listID: string): Promise<ListRows> {
  const [list, items, members] = await Promise.all([
    client.from("shopping_lists").select("id, name").eq("id", listID).single(),
    allRows(
      (from, to) =>
        client
          .from("shopping_items")
          .select("id, name, quantity, unit, aisle, product_id, is_checked, source")
          .eq("list_id", listID)
          .is("deleted_at", null)
          .order("id")
          .range(from, to) as unknown as Page,
    ),
    client.from("shopping_list_members").select("user_id, role, display_name").eq("list_id", listID).order("joined_at").order("user_id"),
  ]);
  for (const answer of [list, members]) if (answer.error) throw failure(answer.error);
  const listRow = list.data as Row;
  return {
    list: { id: listRow.id as string, name: listRow.name as string },
    items: items.map(
      (row): ShoppingItemRow => ({
        id: row.id as string,
        name: row.name as string,
        quantity: row.quantity === null ? undefined : Number(row.quantity),
        unit: optional<string>(row.unit),
        aisle: row.aisle as string,
        productID: optional<string>(row.product_id),
        isChecked: row.is_checked as boolean,
        source: row.source as string,
      }),
    ),
    members: (members.data as Row[]).map((row) => ({
      userID: row.user_id as string,
      role: row.role as ListMember["role"],
      displayName: row.display_name as string,
    })),
  };
}

/**
 * The supermarkets, the user's favourites, and the offers of those still valid from `today` and at most 26 hours old.
 * Thousands of rows per shop: read when the list opens and when the favourites change, not after every tick.
 */
export async function loadOffers(client: SupabaseClient, today: IsoDay, now: Date): Promise<OfferRows> {
  const [supermarkets, favorites] = await Promise.all([
    client.from("supermarkets").select("id, name").order("name"),
    client.from("favorite_supermarkets").select("supermarket_id").is("deleted_at", null),
  ]);
  for (const answer of [supermarkets, favorites]) if (answer.error) throw failure(answer.error);
  const favoriteIDs = [...new Set((favorites.data as Row[]).map((row) => row.supermarket_id as string))].sort();
  const offers =
    favoriteIDs.length === 0
      ? []
      : await allRows(
          (from, to) =>
            client
              .from("offers")
              .select("id, supermarket_id, title, brand, gtin, quantity_value, quantity_unit, price_cents, valid_from, valid_to")
              .in("supermarket_id", favoriteIDs)
              .gte("valid_to", today)
              .gte("fetched_at", new Date(now.getTime() - offerLifetimeMs).toISOString())
              .order("id")
              .range(from, to) as unknown as Page,
        );
  return {
    supermarkets: (supermarkets.data as Row[]).map((row) => ({ id: row.id as string, name: row.name as string })),
    favoriteSupermarketIDs: favoriteIDs,
    offers: offers.map(
      (row): OfferRow => ({
        id: row.id as string,
        supermarketID: row.supermarket_id as string,
        title: row.title as string,
        brand: optional<string>(row.brand),
        gtin: optional<string>(row.gtin),
        quantityValue: row.quantity_value === null ? undefined : Number(row.quantity_value),
        quantityUnit: optional<string>(row.quantity_unit),
        priceCents: row.price_cents as number,
        validFrom: row.valid_from as IsoDay,
        validTo: row.valid_to as IsoDay,
      }),
    ),
  };
}

/** Everything the list screen reads (loadList and loadOffers together). */
export async function loadShopping(client: SupabaseClient, listID: string, today: IsoDay, now: Date): Promise<ShoppingRows> {
  const [list, offers] = await Promise.all([loadList(client, listID), loadOffers(client, today, now)]);
  return { ...list, ...offers };
}

/** The lines of the recipes the menu plans, for what it needs on the list. */
export async function loadRecipeIngredients(client: SupabaseClient, recipeIDs: string[]): Promise<RecipeIngredientRow[]> {
  const ids = [...new Set(recipeIDs)];
  if (ids.length === 0) return [];
  const { data, error } = await client
    .from("recipe_ingredients")
    .select("recipe_id, product_id, name, quantity, unit, aisle, position")
    .in("recipe_id", ids)
    .is("deleted_at", null);
  if (error) throw failure(error);
  return (data as Row[]).map((row) => ({
    recipeID: row.recipe_id as string,
    productID: optional<string>(row.product_id),
    name: row.name as Localized,
    quantity: Number(row.quantity),
    unit: row.unit as string,
    aisle: row.aisle as string,
    position: row.position as number,
  }));
}

function itemRow(userID: string, listID: string, item: NewShoppingItem, source: "manual" | "menu", stamp: string) {
  return {
    id: crypto.randomUUID(),
    list_id: listID,
    name: item.name,
    quantity: item.quantity ?? null,
    unit: item.unit ?? null,
    aisle: item.aisle,
    product_id: item.productID ?? null,
    source,
    updated_by: userID,
    updated_at: stamp,
  };
}

/** An item FitlingCore accepted (shoppingNewItem, shoppingRefill). */
export async function addItem(client: SupabaseClient, userID: string, listID: string, item: NewShoppingItem, source: "manual" | "menu", now: Date) {
  await write(client.from("shopping_items").insert(itemRow(userID, listID, item, source, now.toISOString())));
}

export async function toggleItem(client: SupabaseClient, userID: string, item: { id: string; isChecked: boolean }, now: Date) {
  await write(client.from("shopping_items").update({ is_checked: !item.isChecked, updated_by: userID, updated_at: now.toISOString() }).eq("id", item.id));
}

export async function removeItem(client: SupabaseClient, userID: string, itemID: string, now: Date) {
  const stamp = now.toISOString();
  await write(client.from("shopping_items").update({ deleted_at: stamp, updated_by: userID, updated_at: stamp }).eq("id", itemID));
}

/** Takes everything in the basket off the list (ShoppingStore.clearChecked). */
export async function clearChecked(client: SupabaseClient, userID: string, listID: string, now: Date) {
  const stamp = now.toISOString();
  await write(
    client
      .from("shopping_items")
      .update({ deleted_at: stamp, updated_by: userID, updated_at: stamp })
      .eq("list_id", listID)
      .eq("is_checked", true)
      .is("deleted_at", null),
  );
}

/** What FitlingCore decided for the menu (shoppingRefill): earlier menu items go, what the menu needs comes. */
export async function applyRefill(
  client: SupabaseClient,
  userID: string,
  listID: string,
  change: { removed: string[]; added: NewShoppingItem[] },
  now: Date,
) {
  const stamp = now.toISOString();
  if (change.removed.length > 0) {
    await write(client.from("shopping_items").update({ deleted_at: stamp, updated_by: userID, updated_at: stamp }).in("id", change.removed));
  }
  if (change.added.length > 0) {
    await write(client.from("shopping_items").insert(change.added.map((item) => itemRow(userID, listID, item, "menu", stamp))));
  }
}

/** A supermarket whose offers the user wants to see, or no longer (ShoppingStore.setFavorite): one row, revived. */
export async function setFavoriteSupermarket(client: SupabaseClient, userID: string, supermarketID: string, favorite: boolean, now: Date) {
  const { data, error } = await client.from("favorite_supermarkets").select("id, deleted_at").eq("supermarket_id", supermarketID);
  if (error) throw failure(error);
  const rows = data as Row[];
  const stamp = now.toISOString();
  if (favorite) {
    if (rows.some((row) => row.deleted_at === null)) return;
    if (rows.length > 0) {
      await write(client.from("favorite_supermarkets").update({ deleted_at: null, updated_at: stamp }).eq("id", rows[0].id as string));
    } else {
      await write(client.from("favorite_supermarkets").insert({ id: crypto.randomUUID(), user_id: userID, supermarket_id: supermarketID, updated_at: stamp }));
    }
  } else {
    const alive = rows.filter((row) => row.deleted_at === null).map((row) => row.id as string);
    if (alive.length > 0) await write(client.from("favorite_supermarkets").update({ deleted_at: stamp, updated_at: stamp }).in("id", alive));
  }
}

/** What went wrong with sharing, as the String Catalog key the screen shows (SharingError.messageKey). */
function sharingFailure(error: { message: string }): Error {
  if (error.message.includes("invalid_invite")) return new Error("shopping.error.invalidInvite");
  if (error.message.includes("list_full")) return new Error("shopping.error.listFull");
  return failure(error);
}

/** A code valid for seven days, shown only once (create_shopping_list_invite). */
export async function createInvite(client: SupabaseClient, listID: string): Promise<string> {
  const { data, error } = await client.rpc("create_shopping_list_invite", { list: listID });
  if (error) throw sharingFailure(error);
  return data as string;
}

/** Joins the list of the code under `name`, as the other members will see it; answers the list's id. */
export async function joinList(client: SupabaseClient, code: string, name: string): Promise<string> {
  const { data, error } = await client.rpc("join_shopping_list", { invite_code: code.trim(), member_name: limitedText(name.trim(), 40) });
  if (error) throw sharingFailure(error);
  return data as string;
}

/** Leaves the list; the server makes the longest member its owner, or removes a list nobody is on. */
export async function leaveList(client: SupabaseClient, listID: string, userID: string) {
  const { error } = await client.from("shopping_list_members").delete().eq("list_id", listID).eq("user_id", userID);
  if (error) throw sharingFailure(error);
}
