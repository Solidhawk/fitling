import { readFile } from "node:fs/promises";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, test } from "vitest";
import { type FitlingCore, loadCore, type ShoppingInput } from "../core/fitlingCore";
import { applyMenuChange, loadMenu } from "./menu";
import {
  addItem,
  applyRefill,
  createInvite,
  ensureList,
  joinList,
  leaveList,
  loadList,
  loadOffers,
  loadRecipeIngredients,
  setFavoriteSupermarket,
  type ShoppingRows,
  toggleItem,
} from "./shopping";

// Against the local Supabase that CI starts (never the real project); ShoppingTests on iOS.
const url = process.env.VITE_SUPABASE_URL;
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const serviceKey = process.env.LOCAL_SUPABASE_SERVICE_KEY;
const today = new Date().toISOString().slice(0, 10);

describe.skipIf(!url || !key || !serviceKey)("the shopping list on the server", () => {
  let core: FitlingCore;
  let admin: SupabaseClient;

  beforeAll(async () => {
    const file = await readFile(new URL("../../public/fitling-core.wasm", import.meta.url));
    core = await loadCore(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer);
    admin = createClient(url!, serviceKey!, { auth: { persistSession: false } });
  });

  async function user() {
    const email = `shopping-${crypto.randomUUID()}@fitling.test`;
    const password = "lang-genoeg-wachtwoord-1";
    const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (created.error) throw created.error;
    const client = createClient(url!, key!, { auth: { persistSession: false } });
    const signIn = await client.auth.signInWithPassword({ email, password });
    if (signIn.error) throw signIn.error;
    return { id: created.data.user.id, client };
  }

  /** Everything the list screen reads, as it reads it: the list and the offers. */
  async function loadShopping(client: SupabaseClient, listID: string): Promise<ShoppingRows> {
    const [list, offers] = await Promise.all([loadList(client, listID), loadOffers(client, today, new Date())]);
    return { ...list, ...offers };
  }

  function input(rows: ShoppingRows): ShoppingInput {
    return { today, items: rows.items, offers: rows.offers, supermarkets: rows.supermarkets, favoriteSupermarketIDs: rows.favoriteSupermarketIDs, confirmedOfferIDs: [] };
  }

  test("aSharedListIsSeenByBothMembers", async () => {
    const owner = await user();
    const list = await ensureList(owner.client, owner.id, "Boodschappen", "Anna", new Date());
    // The same list the next time, made once.
    expect((await ensureList(owner.client, owner.id, "Andere", "Anna", new Date())).id).toBe(list.id);
    await addItem(owner.client, owner.id, list.id, core.shoppingNewItem({ text: " Melk " }).item!, "manual", new Date());
    const code = await createInvite(owner.client, list.id);
    expect(code).toMatch(/^[0-9A-F]{12}$/);

    // The guest opened the list screen before, so they have a list of their own, here one that sorts first.
    const guest = await user();
    const own = await ensureList(guest.client, guest.id, "Aaa eigen lijst", "Bram", new Date());
    const joined = await joinList(guest.client, code.toLowerCase(), "Bram");
    expect(joined).toBe(list.id);
    expect((await ensureList(guest.client, guest.id, "Boodschappen", "Bram", new Date())).id).toBe(own.id);
    // The list of the code, which the screen remembers, comes first.
    const seen = await loadShopping(guest.client, (await ensureList(guest.client, guest.id, "Boodschappen", "Bram", new Date(), joined)).id);
    expect(seen.list.id).toBe(list.id);
    expect(seen.items.map((item) => item.name)).toEqual(["Melk"]);
    expect(seen.members.map((member) => [member.displayName, member.role])).toEqual([
      ["Anna", "owner"],
      ["Bram", "member"],
    ]);
    await toggleItem(guest.client, guest.id, seen.items[0], new Date());
    expect((await loadShopping(owner.client, list.id)).items[0].isChecked).toBe(true);

    // Someone without the code sees nothing of it and cannot add to it.
    const stranger = await user();
    const { data } = await stranger.client.from("shopping_lists").select("id").eq("id", list.id);
    expect(data).toEqual([]);
    await expect(addItem(stranger.client, stranger.id, list.id, { name: "Kaas", aisle: "dairy" }, "manual", new Date())).rejects.toThrow();

    // After leaving, the list is gone for the guest and stays for the owner.
    await leaveList(guest.client, list.id, guest.id);
    const after = await guest.client.from("shopping_items").select("id").eq("list_id", list.id);
    expect(after.data).toEqual([]);
    expect((await loadShopping(owner.client, list.id)).members.map((member) => member.displayName)).toEqual(["Anna"]);
  });

  // Ten people at most on a list (join_shopping_list): the eleventh is told the list is full, and someone already on
  // it can use the code again (UNFORGET S48).
  test("aFullListSaysSo", async () => {
    const owner = await user();
    const list = await ensureList(owner.client, owner.id, "Boodschappen", "Anna", new Date());
    const code = await createInvite(owner.client, list.id);
    const members = [];
    for (let index = 0; index < 9; index++) {
      const member = await user();
      await joinList(member.client, code, `Lid ${index + 1}`);
      members.push(member);
    }
    const late = await user();
    await expect(joinList(late.client, code, "Te laat")).rejects.toThrow("shopping.error.listFull");
    expect(await joinList(members[0].client, code, "Lid 1")).toBe(list.id);
    expect((await loadShopping(owner.client, list.id)).members).toHaveLength(10);
  });

  test("aWrongCodeSaysSo", async () => {
    const guest = await user();
    await expect(joinList(guest.client, "000000000000", "Bram")).rejects.toThrow("shopping.error.invalidInvite");
  });

  test("oldOffersAreLeftOut", async () => {
    const shopper = await user();
    const shop = `test_${crypto.randomUUID().replace(/-/g, "").slice(0, 10)}`;
    const stored = await admin.from("supermarkets").insert({ id: shop, name: "Proefmarkt" });
    if (stored.error) throw stored.error;
    const yesterday = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);
    const week = new Date(Date.now() + 6 * 86_400_000).toISOString().slice(0, 10);
    // Every row with the same columns: in a bulk insert, a column one row leaves out becomes null, not its default.
    const offer = (title: string, values: Record<string, unknown>) => ({
      supermarket_id: shop,
      external_id: crypto.randomUUID(),
      title,
      price_cents: 99,
      valid_from: today,
      valid_to: week,
      fetched_at: new Date().toISOString(),
      ...values,
    });
    const offers = await admin.from("offers").insert([
      offer("Vers", {}),
      // Not refreshed by the nightly job: PrijsProfeet's terms keep it out of sight.
      offer("Oud", { fetched_at: new Date(Date.now() - 30 * 3_600_000).toISOString() }),
      offer("Verlopen", { valid_from: yesterday, valid_to: yesterday }),
    ]);
    if (offers.error) throw offers.error;
    const list = await ensureList(shopper.client, shopper.id, "Boodschappen", "Anna", new Date());
    expect((await loadShopping(shopper.client, list.id)).offers).toEqual([]);
    await setFavoriteSupermarket(shopper.client, shopper.id, shop, true, new Date());
    await setFavoriteSupermarket(shopper.client, shopper.id, shop, true, new Date());
    const rows = await loadShopping(shopper.client, list.id);
    expect(rows.favoriteSupermarketIDs).toEqual([shop]);
    expect(rows.offers.map((row) => row.title)).toEqual(["Vers"]);
    expect(rows.supermarkets).toContainEqual({ id: shop, name: "Proefmarkt" });
    await setFavoriteSupermarket(shopper.client, shopper.id, shop, false, new Date());
    expect((await loadShopping(shopper.client, list.id)).offers).toEqual([]);
  });

  test("refillingFromTheMenuReplacesMenuItems", async () => {
    const cook = await user();
    const menuRows = await loadMenu(cook.client, today);
    const menu = () => loadMenu(cook.client, today).then(({ steps: _, ...rows }) => ({ userID: cook.id, today, languages: ["nl"], ...rows }));
    await applyMenuChange(cook.client, cook.id, core.menuGenerate({ menu: await menu(), days: 1, seed: "5", targets: { kcal: 2200, proteinG: 120, carbsG: 250, fatG: 70 } }), new Date());
    expect(menuRows.recipes.length).toBeGreaterThan(0);
    const list = await ensureList(cook.client, cook.id, "Boodschappen", "Anna", new Date());
    await addItem(cook.client, cook.id, list.id, { name: "Koffie", aisle: "other" }, "manual", new Date());
    const fill = async () => {
      const book = await menu();
      const ingredients = await loadRecipeIngredients(cook.client, book.entries.map((entry) => entry.recipeID));
      const rows = await loadShopping(cook.client, list.id);
      await applyRefill(cook.client, cook.id, list.id, core.shoppingRefill({ shopping: input(rows), menu: book, ingredients }), new Date());
      return loadShopping(cook.client, list.id);
    };
    const first = await fill();
    const fromMenu = first.items.filter((item) => item.source === "menu");
    expect(fromMenu.length).toBeGreaterThan(0);
    const second = await fill();
    expect(second.items.filter((item) => item.source === "menu").map((item) => item.name).sort()).toEqual(fromMenu.map((item) => item.name).sort());
    expect(second.items.some((item) => fromMenu.some((old) => old.id === item.id))).toBe(false);
    expect(second.items.find((item) => item.name === "Koffie")?.source).toBe("manual");
  });
});
