import type { SupabaseClient } from "@supabase/supabase-js";
import type { IsoDay, Localized, LoggedMeal, MenuChange, MenuInput, MenuPreferences, MenuRecipe } from "../core/fitlingCore";
import { failure } from "./failure";
import { allRows, type Keyset, type Row } from "./pages";

/** The recipes, week menu and preferences of the user and the shared recipes, as FitlingCore reads them, plus the steps. */
export type MenuRows = Omit<MenuInput, "userID" | "today" | "languages"> & {
  /** Per recipe id, per language the steps. */
  steps: Record<string, Record<string, string[]>>;
};

/** One line of a recipe, in its order (RecipeIngredient on iOS). */
export interface Ingredient {
  name: Localized;
  quantity: number;
  /** g, ml, piece, tbsp or tsp. */
  unit: string;
}

/** The meals in the order a day has them (MealSlot.allCases). */
export const mealSlots = ["breakfast", "lunch", "dinner", "snack"] as const;

/** Until the user saves preferences: the defaults of `menu_preferences` (MenuStore.preferences). */
export const defaultPreferences: MenuPreferences = { excludedTags: [], mealPrep: false, mealSlots: ["breakfast", "lunch", "dinner"] };

const optional = <T>(value: unknown) => (value === null || value === undefined ? undefined : (value as T));

const recipeColumns =
  "id, owner_id, title, steps, servings, cook_minutes, kcal_per_serving, protein_g_per_serving, carbs_g_per_serving, fat_g_per_serving, cost_cents_per_serving, keeps_well, meal_slots, tags";

function recipeFromRow(row: Row, productIDs: string[]): MenuRecipe {
  return {
    id: row.id as string,
    ownerID: optional<string>(row.owner_id),
    title: row.title as Localized,
    servings: row.servings as number,
    cookMinutes: row.cook_minutes as number,
    kcalPerServing: Number(row.kcal_per_serving),
    proteinGPerServing: Number(row.protein_g_per_serving),
    carbsGPerServing: Number(row.carbs_g_per_serving),
    fatGPerServing: Number(row.fat_g_per_serving),
    costCentsPerServing: optional<number>(row.cost_cents_per_serving),
    keepsWell: row.keeps_well as boolean,
    mealSlots: row.meal_slots as string[],
    tags: row.tags as string[],
    productIDs,
  };
}

/** The part of a supabase-js query that `rows` narrows with. */
interface Filter extends Keyset {
  not(column: string, operator: "is", value: null): Filter;
  gte(column: string, value: string): Filter;
}

/** Every row of `table` that is not removed, page by page, narrowed by `narrow`. */
function rows(client: SupabaseClient, table: string, columns: string, narrow: (query: Filter) => Filter = (query) => query) {
  return allRows(() => narrow(client.from(table).select(columns).is("deleted_at", null) as unknown as Filter));
}

async function write(work: PromiseLike<{ error: { message: string } | null }>) {
  const { error } = await work;
  if (error) throw failure(error);
}

/**
 * Everything the menu tab reads (MenuStore on iOS): shared and own recipes with the products in them, the week menu
 * from `today`, the preferences and the products the user leaves out. Row-level security keeps it to the user's own
 * rows and the shared ones.
 */
export async function loadMenu(client: SupabaseClient, today: IsoDay): Promise<MenuRows> {
  const [recipes, ingredients, entries, excluded, preferences] = await Promise.all([
    rows(client, "recipes", recipeColumns),
    rows(client, "recipe_ingredients", "id, recipe_id, product_id", (query) => query.not("product_id", "is", null)),
    rows(client, "meal_plan_entries", "id, planned_on, meal, recipe_id, servings, is_leftover, is_pinned, logged_entry_id", (query) =>
      query.gte("planned_on", today),
    ),
    rows(client, "excluded_ingredients", "id, product_id"),
    client.from("menu_preferences").select("excluded_tags, max_cook_minutes, budget_cents, meal_prep, meal_slots").maybeSingle(),
  ]);
  if (preferences.error) throw failure(preferences.error);
  const products = new Map<string, string[]>();
  for (const row of ingredients) {
    const recipeID = row.recipe_id as string;
    products.set(recipeID, [...(products.get(recipeID) ?? []), row.product_id as string]);
  }
  const saved = preferences.data as Row | null;
  // Recipes removed after they were planned (on another device): their meals keep name and values (MenuBook.recipe).
  const alive = new Set(recipes.map((row) => row.id as string));
  const missing = [...new Set(entries.map((row) => row.recipe_id as string))].filter((id) => !alive.has(id));
  let removed: Row[] = [];
  if (missing.length > 0) {
    const found = await client.from("recipes").select(recipeColumns).in("id", missing);
    if (found.error) throw failure(found.error);
    removed = (found.data ?? []) as unknown as Row[];
  }
  return {
    recipes: recipes.map((row) => recipeFromRow(row, products.get(row.id as string) ?? [])),
    removedRecipes: removed.map((row) => recipeFromRow(row, [])),
    steps: Object.fromEntries(
      [...recipes, ...removed].map((row) => [row.id as string, (row.steps as Record<string, string[]> | null) ?? {}]),
    ),
    entries: entries.map((row) => ({
      id: row.id as string,
      plannedOn: row.planned_on as IsoDay,
      meal: row.meal as string,
      recipeID: row.recipe_id as string,
      servings: Number(row.servings),
      isLeftover: row.is_leftover as boolean,
      isPinned: row.is_pinned as boolean,
      loggedEntryID: optional<string>(row.logged_entry_id),
    })),
    settings: saved
      ? {
          excludedTags: saved.excluded_tags as string[],
          maxCookMinutes: optional<number>(saved.max_cook_minutes),
          budgetCents: optional<number>(saved.budget_cents),
          mealPrep: saved.meal_prep as boolean,
          mealSlots: saved.meal_slots as string[],
        }
      : defaultPreferences,
    excludedProductIDs: excluded.map((row) => row.product_id as string),
  };
}

/** What the recipe detail lists, in its order. */
export async function recipeIngredients(client: SupabaseClient, recipeID: string): Promise<Ingredient[]> {
  const { data, error } = await client
    .from("recipe_ingredients")
    .select("name, quantity, unit")
    .eq("recipe_id", recipeID)
    .is("deleted_at", null)
    .order("position");
  if (error) throw failure(error);
  return (data as Row[]).map((row) => ({ name: row.name as Localized, quantity: Number(row.quantity), unit: row.unit as string }));
}

// MARK: Week menu

/** What FitlingCore decided (menuGenerate, menuRenew): the meals that go are removed, those that come are stored. */
export async function applyMenuChange(client: SupabaseClient, userID: string, change: MenuChange, now: Date) {
  const stamp = now.toISOString();
  if (change.removed.length > 0) {
    await write(client.from("meal_plan_entries").update({ deleted_at: stamp, updated_at: stamp }).in("id", change.removed));
  }
  if (change.added.length > 0) {
    await write(
      client.from("meal_plan_entries").insert(
        change.added.map((meal) => ({
          id: crypto.randomUUID(),
          user_id: userID,
          planned_on: meal.day,
          meal: meal.slot,
          recipe_id: meal.recipeID,
          servings: meal.servings,
          is_leftover: meal.isLeftover,
          updated_at: stamp,
        })),
      ),
    );
  }
}

/** A pinned meal stays when a new menu is made (MenuStore.togglePin). */
export async function setPinned(client: SupabaseClient, entryID: string, pinned: boolean, now: Date) {
  await write(client.from("meal_plan_entries").update({ is_pinned: pinned, updated_at: now.toISOString() }).eq("id", entryID));
}

/** Another recipe for a meal not yet logged; a meal the user chose is pinned, so a new menu keeps it (MenuStore.swap). */
export async function swapRecipe(client: SupabaseClient, entryID: string, recipeID: string, now: Date) {
  await write(
    client
      .from("meal_plan_entries")
      .update({ recipe_id: recipeID, is_leftover: false, is_pinned: true, updated_at: now.toISOString() })
      .eq("id", entryID)
      .is("logged_entry_id", null),
  );
}

export async function removeEntry(client: SupabaseClient, entryID: string, now: Date) {
  const stamp = now.toISOString();
  await write(client.from("meal_plan_entries").update({ deleted_at: stamp, updated_at: stamp }).eq("id", entryID));
}

/**
 * Logs a planned meal with one tap (MenuStore.log): one food entry with what FitlingCore gives for the planned servings
 * (menuLoggedMeal). The meal is marked only while it is not logged yet, so a second tap, here or on another device,
 * takes its food entry back and answers undefined.
 */
export async function logMeal(client: SupabaseClient, userID: string, entryID: string, meal: LoggedMeal, now: Date): Promise<string | undefined> {
  const id = crypto.randomUUID();
  const stamp = now.toISOString();
  await write(
    client.from("food_entries").insert({
      id,
      user_id: userID,
      consumed_on: meal.day,
      meal: meal.slot,
      recipe_id: meal.recipeID,
      name: meal.name,
      quantity: meal.servings,
      quantity_unit: "serving",
      kcal: meal.kcal,
      protein_g: meal.proteinG,
      carbs_g: meal.carbsG,
      fat_g: meal.fatG,
      updated_at: stamp,
    }),
  );
  const marked = await client
    .from("meal_plan_entries")
    .update({ logged_entry_id: id, updated_at: stamp })
    .eq("id", entryID)
    .is("logged_entry_id", null)
    .select("id");
  if (marked.error) throw failure(marked.error);
  if ((marked.data ?? []).length > 0) return id;
  await write(client.from("food_entries").update({ deleted_at: stamp, updated_at: stamp }).eq("id", id));
  // Not marked: logged already or removed, here or on another device, or a change from a device whose clock runs ahead
  // made the server take this one as older (apply_sync_rules). The last is told, so the tap does not do nothing
  // (UNFORGET S46).
  const entry = await client.from("meal_plan_entries").select("logged_entry_id, deleted_at").eq("id", entryID).maybeSingle();
  if (entry.error) throw failure(entry.error);
  if (entry.data && entry.data.logged_entry_id === null && entry.data.deleted_at === null) throw new Error("error.server");
  return undefined;
}

// MARK: Preferences

/** One row per user, changed in place (MenuStore.save). */
export async function savePreferences(client: SupabaseClient, userID: string, preferences: MenuPreferences, now: Date) {
  await write(
    client.from("menu_preferences").upsert({
      user_id: userID,
      excluded_tags: preferences.excludedTags,
      max_cook_minutes: preferences.maxCookMinutes ?? null,
      budget_cents: preferences.budgetCents ?? null,
      meal_prep: preferences.mealPrep,
      meal_slots: mealSlots.filter((slot) => preferences.mealSlots.includes(slot)),
      updated_at: now.toISOString(),
    }),
  );
}

// MARK: Own recipes

/** A recipe of the user's own, as the form holds it; the energy and macros are the user's own numbers per serving. */
export interface OwnRecipe {
  title: string;
  servings: number;
  cookMinutes: number;
  kcal?: number;
  protein?: number;
  carbs?: number;
  fat?: number;
  mealSlots: string[];
  /** Lines without a name or an amount are left out. Each has its id from the moment it was added to the form. */
  ingredients: { id: string; name: string; quantity: number; unit: string }[];
  steps: string[];
}

/**
 * Stores a recipe of the user's own (MenuStore.create) that FitlingCore found complete (ownRecipeComplete): the title
 * and steps under the language the user types in, the lines with a name and an amount, in their order. Saving again
 * after a failure, with the same `id`, stores the recipe once and its lines as the form has them now (UNFORGET S46).
 */
export async function createRecipe(
  client: SupabaseClient,
  userID: string,
  own: OwnRecipe,
  language: string,
  now: Date,
  id: string,
): Promise<string> {
  const stamp = now.toISOString();
  const steps = own.steps.map((step) => step.trim()).filter((step) => step.length > 0);
  await write(
    client.from("recipes").upsert({
      id,
      owner_id: userID,
      title: { [language]: own.title.trim() },
      steps: steps.length > 0 ? { [language]: steps } : {},
      servings: own.servings,
      cook_minutes: own.cookMinutes,
      kcal_per_serving: own.kcal,
      protein_g_per_serving: own.protein,
      carbs_g_per_serving: own.carbs,
      fat_g_per_serving: own.fat,
      meal_slots: mealSlots.filter((slot) => own.mealSlots.includes(slot)),
      deleted_at: null,
      updated_at: stamp,
    }),
  );
  const lines = own.ingredients
    .map((line, position) => ({ ...line, name: line.name.trim(), position }))
    .filter((line) => line.quantity > 0 && line.name.length > 0);
  if (lines.length > 0) {
    await write(
      client.from("recipe_ingredients").upsert(
        lines.map((line) => ({
          id: line.id,
          recipe_id: id,
          owner_id: userID,
          name: { [language]: line.name },
          quantity: line.quantity,
          unit: line.unit,
          position: line.position,
          deleted_at: null,
          updated_at: stamp,
        })),
      ),
    );
  }
  // Lines an earlier try stored that the form no longer has go, as a removal on another device would (deleted_at).
  let gone = client.from("recipe_ingredients").update({ deleted_at: stamp, updated_at: stamp }).eq("recipe_id", id).is("deleted_at", null);
  if (lines.length > 0) gone = gone.not("id", "in", `(${lines.map((line) => line.id).join(",")})`);
  await write(gone);
  return id;
}

/** Removed, not deleted: other devices learn of it through `deleted_at`. Shared recipes are not the user's to remove. */
export async function deleteRecipe(client: SupabaseClient, recipeID: string, now: Date) {
  const stamp = now.toISOString();
  await write(client.from("recipes").update({ deleted_at: stamp, updated_at: stamp }).eq("id", recipeID));
}
