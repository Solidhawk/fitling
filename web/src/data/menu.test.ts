import { readFile } from "node:fs/promises";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, test } from "vitest";
import { type FitlingCore, loadCore, type MenuInput } from "../core/fitlingCore";
import {
  applyMenuChange,
  createRecipe,
  deleteRecipe,
  loadMenu,
  logMeal,
  type MenuRows,
  recipeIngredients,
  removeEntry,
  savePreferences,
  setPinned,
  swapRecipe,
} from "./menu";

// Against the local Supabase that CI starts, with the shared recipes of supabase/seed/recipes.sql (never the real
// project); MenuTests on iOS.
const url = process.env.VITE_SUPABASE_URL;
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const serviceKey = process.env.LOCAL_SUPABASE_SERVICE_KEY;
const today = "2026-11-25";
const targets = { kcal: 2200, proteinG: 120, carbsG: 250, fatG: 70 };

describe.skipIf(!url || !key || !serviceKey)("the week menu on the server", () => {
  let core: FitlingCore;
  let admin: SupabaseClient;

  beforeAll(async () => {
    const file = await readFile(new URL("../../public/fitling-core.wasm", import.meta.url));
    core = await loadCore(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength) as ArrayBuffer);
    admin = createClient(url!, serviceKey!, { auth: { persistSession: false } });
  });

  async function user() {
    const email = `menu-${crypto.randomUUID()}@fitling.test`;
    const password = "lang-genoeg-wachtwoord-1";
    const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (created.error) throw created.error;
    const client = createClient(url!, key!, { auth: { persistSession: false } });
    const signIn = await client.auth.signInWithPassword({ email, password });
    if (signIn.error) throw signIn.error;
    return { id: created.data.user.id, client };
  }

  function input(userID: string, rows: MenuRows): MenuInput {
    const { steps: _, ...book } = rows;
    return { userID, today, languages: ["nl"], ...book };
  }

  test("aNewMenuIsStoredAndPinnedMealsStay", async () => {
    const { id, client } = await user();
    const empty = await loadMenu(client, today);
    // The defaults until the user saves preferences (MenuStore.preferences).
    expect(empty.settings).toEqual({ excludedTags: [], mealPrep: false, mealSlots: ["breakfast", "lunch", "dinner"] });
    expect(empty.entries).toEqual([]);
    const first = core.menuGenerate({ menu: input(id, empty), days: 7, seed: "1", targets });
    expect(first.added.length).toBe(7 * 3);
    await applyMenuChange(client, id, first, new Date());
    const planned = await loadMenu(client, today);
    expect(planned.entries).toHaveLength(21);
    const pinned = planned.entries.find((entry) => entry.plannedOn === today && entry.meal === "dinner")!;
    await setPinned(client, pinned.id, true, new Date());
    const second = core.menuGenerate({ menu: input(id, await loadMenu(client, today)), days: 7, seed: "2", targets });
    await applyMenuChange(client, id, second, new Date());
    const after = await loadMenu(client, today);
    expect(after.entries).toHaveLength(21);
    expect(after.entries.find((entry) => entry.id === pinned.id)).toMatchObject({ isPinned: true, recipeID: pinned.recipeID });
    expect(after.entries.filter((entry) => entry.id !== pinned.id).every((entry) => !planned.entries.some((old) => old.id === entry.id))).toBe(true);
  });

  test("aSwappedMealIsPinnedAndARemovedOneGoes", async () => {
    const { id, client } = await user();
    await applyMenuChange(client, id, core.menuGenerate({ menu: input(id, await loadMenu(client, today)), days: 1, seed: "3", targets }), new Date());
    const rows = await loadMenu(client, today);
    const [lunch] = rows.entries.filter((entry) => entry.meal === "lunch");
    const other = core.menuRecipesFor({ menu: input(id, rows), entryID: lunch.id })[0];
    await swapRecipe(client, lunch.id, other.id, new Date());
    const breakfast = rows.entries.find((entry) => entry.meal === "breakfast")!;
    await removeEntry(client, breakfast.id, new Date());
    const after = await loadMenu(client, today);
    expect(after.entries.find((entry) => entry.id === lunch.id)).toMatchObject({ recipeID: other.id, isPinned: true, isLeftover: false });
    expect(after.entries.some((entry) => entry.id === breakfast.id)).toBe(false);
  });

  test("loggingTwiceLogsOnce", async () => {
    const { id, client } = await user();
    await applyMenuChange(client, id, core.menuGenerate({ menu: input(id, await loadMenu(client, today)), days: 1, seed: "4", targets }), new Date());
    const rows = await loadMenu(client, today);
    const dinner = rows.entries.find((entry) => entry.meal === "dinner")!;
    const meal = core.menuLoggedMeal({ menu: input(id, rows), entryID: dinner.id }).meal!;
    // Two taps on the same screen, before it read the menu again: the second does nothing.
    expect(await logMeal(client, id, dinner.id, meal, new Date())).toBeDefined();
    expect(await logMeal(client, id, dinner.id, meal, new Date())).toBeUndefined();
    const { data } = await client.from("food_entries").select("recipe_id, meal, quantity, quantity_unit, kcal, consumed_on").is("deleted_at", null);
    // The diary keeps amounts to a tenth (food_entries.quantity), the menu to a quarter serving.
    expect(data).toEqual([
      { recipe_id: meal.recipeID, meal: "dinner", quantity: Math.round(meal.servings * 10) / 10, quantity_unit: "serving", kcal: meal.kcal, consumed_on: today },
    ]);
    const after = await loadMenu(client, today);
    expect(after.entries.find((entry) => entry.id === dinner.id)?.loggedEntryID).toBeDefined();
    expect(core.menuLoggedMeal({ menu: input(id, after), entryID: dinner.id }).meal).toBeUndefined();
  });

  test("ownRecipesAreSavedAndRemoved", async () => {
    const { id, client } = await user();
    const recipeID = await createRecipe(
      client,
      id,
      {
        title: "  Pasta pesto ",
        servings: 2,
        cookMinutes: 20,
        kcal: 550,
        protein: 18,
        carbs: 70,
        fat: 20,
        mealSlots: ["dinner", "lunch"],
        ingredients: [
          { id: crypto.randomUUID(), name: "Pasta", quantity: 200, unit: "g" },
          { id: crypto.randomUUID(), name: "", quantity: 1, unit: "piece" },
          { id: crypto.randomUUID(), name: "Pesto", quantity: 0, unit: "tbsp" },
        ],
        steps: ["Kook de pasta.", " ", "Roer de pesto erdoor."],
      },
      "nl",
      new Date(),
      crypto.randomUUID(),
    );
    const rows = await loadMenu(client, today);
    const own = rows.recipes.find((recipe) => recipe.id === recipeID)!;
    expect(own).toMatchObject({ ownerID: id, title: { nl: "Pasta pesto" }, servings: 2, cookMinutes: 20, kcalPerServing: 550, mealSlots: ["lunch", "dinner"], productIDs: [] });
    expect(rows.steps[recipeID]).toEqual({ nl: ["Kook de pasta.", "Roer de pesto erdoor."] });
    expect(await recipeIngredients(client, recipeID)).toEqual([{ name: { nl: "Pasta" }, quantity: 200, unit: "g" }]);
    await deleteRecipe(client, recipeID, new Date());
    expect((await loadMenu(client, today)).recipes.some((recipe) => recipe.id === recipeID)).toBe(false);
  });

  // An answer that got lost: saving again with the same id stores no second recipe and no second set of lines.
  test("anOwnRecipeSavedTwiceIsStoredOnce", async () => {
    const { id, client } = await user();
    const recipeID = crypto.randomUUID();
    const own = {
      title: "Soep",
      servings: 2,
      cookMinutes: 30,
      kcal: 300,
      protein: 12,
      carbs: 30,
      fat: 10,
      mealSlots: ["lunch"],
      ingredients: [{ id: crypto.randomUUID(), name: "Tomaat", quantity: 4, unit: "piece" }],
      steps: [],
    };
    await createRecipe(client, id, own, "nl", new Date(), recipeID);
    await createRecipe(client, id, own, "nl", new Date(), recipeID);
    const rows = await loadMenu(client, today);
    expect(rows.recipes.filter((recipe) => recipe.ownerID === id).map((recipe) => recipe.id)).toEqual([recipeID]);
    expect(await recipeIngredients(client, recipeID)).toEqual([{ name: { nl: "Tomaat" }, quantity: 4, unit: "piece" }]);
    // Changed in the form before saving again: the lines are the ones it has now.
    await createRecipe(client, id, { ...own, ingredients: [{ id: crypto.randomUUID(), name: "Ui", quantity: 1, unit: "piece" }] }, "nl", new Date(), recipeID);
    expect(await recipeIngredients(client, recipeID)).toEqual([{ name: { nl: "Ui" }, quantity: 1, unit: "piece" }]);
  });

  test("preferencesAreKept", async () => {
    const { id, client } = await user();
    await savePreferences(client, id, { excludedTags: ["meat"], maxCookMinutes: 30, mealPrep: true, mealSlots: ["lunch", "dinner"] }, new Date());
    await savePreferences(client, id, { excludedTags: ["meat", "fish"], maxCookMinutes: 30, budgetCents: 500, mealPrep: true, mealSlots: ["lunch", "dinner"] }, new Date());
    expect((await loadMenu(client, today)).settings).toEqual({
      excludedTags: ["meat", "fish"],
      maxCookMinutes: 30,
      budgetCents: 500,
      mealPrep: true,
      mealSlots: ["lunch", "dinner"],
    });
  });
});
