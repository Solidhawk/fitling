import { expect, type Page } from "./fixtures";
import { admin, createUser, localDay, nl, signIn } from "./users";

/** A shared recipe of supabase/seed/recipes.sql for a meal, with its Dutch title. */
export async function sharedRecipe(slot: string, skip = 0): Promise<{ id: string; title: string; kcal: number }> {
  const { data, error } = await admin
    .from("recipes")
    .select("id, title, kcal_per_serving")
    .is("owner_id", null)
    .contains("meal_slots", [slot])
    .order("id")
    .range(skip, skip);
  if (error) throw error;
  const row = data[0] as { id: string; title: { nl: string }; kcal_per_serving: number };
  return { id: row.id, title: row.title.nl, kcal: Number(row.kcal_per_serving) };
}

/** Today's breakfast, lunch and dinner on the user's menu, as a menu the app made; answers the entries' ids. */
export async function todaysMenu(userID: string): Promise<{ id: string; slot: string; recipe: { id: string; title: string; kcal: number } }[]> {
  const planned = [];
  for (const slot of ["breakfast", "lunch", "dinner"]) {
    planned.push({ id: crypto.randomUUID(), slot, recipe: await sharedRecipe(slot) });
  }
  const stored = await admin.from("meal_plan_entries").insert(
    planned.map((meal) => ({
      id: meal.id,
      user_id: userID,
      planned_on: localDay(),
      meal: meal.slot,
      recipe_id: meal.recipe.id,
      servings: 1,
      updated_at: new Date().toISOString(),
    })),
  );
  if (stored.error) throw stored.error;
  return planned;
}

/** Signed in with a profile and a partner, on the menu tab. */
export async function openMenu(page: Page, prepare?: (userID: string) => Promise<void>) {
  const user = await createUser({ profile: true, creature: true });
  await prepare?.(user.id);
  await signIn(page, user.email);
  await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
  await page.getByRole("tab", { name: nl("menu.title") }).click();
  await expect(page.getByTestId("menu.recipes")).toBeVisible({ timeout: 15_000 });
  return user;
}
