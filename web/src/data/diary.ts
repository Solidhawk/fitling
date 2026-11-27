import type { SupabaseClient } from "@supabase/supabase-js";
import type { FitlingCore, IsoDay, QuantityUnit } from "../core/fitlingCore";
import { failure } from "./failure";
import { keep, kept, keptAnswer, rowsBetween, send } from "./offline";
import { allRows } from "./pages";
import { type Product, productName, productsByID } from "./products";

export type Meal = "breakfast" | "lunch" | "dinner" | "snack";
export const meals: Meal[] = ["breakfast", "lunch", "dinner", "snack"];

/** One thing eaten, as it was when it was logged (FoodEntry on iOS): a later change to the product leaves it as it is. */
export interface FoodEntry {
  id: string;
  consumedOn: IsoDay;
  meal: Meal;
  productID?: string;
  name: string;
  quantity: number;
  quantityUnit: QuantityUnit;
  kcal: number;
  proteinG?: number;
  carbsG?: number;
  fatG?: number;
  updatedAt: string;
}

type Row = Record<string, unknown>;
type KeptRow = Row & { id: string };

function maybe(value: unknown): number | undefined {
  return value === null || value === undefined ? undefined : Number(value);
}

function entryFromRow(row: Row): FoodEntry {
  return {
    id: row.id as string,
    consumedOn: row.consumed_on as string,
    meal: row.meal as Meal,
    productID: (row.product_id as string | null) ?? undefined,
    name: row.name as string,
    quantity: Number(row.quantity),
    quantityUnit: row.quantity_unit as QuantityUnit,
    kcal: Number(row.kcal),
    proteinG: maybe(row.protein_g),
    carbsG: maybe(row.carbs_g),
    fatG: maybe(row.fat_g),
    updatedAt: row.updated_at as string,
  };
}

function inOrder(rows: Row[]): FoodEntry[] {
  return rows.map(entryFromRow).sort((a, b) => Date.parse(a.updatedAt) - Date.parse(b.updatedAt));
}

/**
 * What was logged on a day, in the order it was logged (FoodDiary.entries); without a connection as this browser last
 * knew it, with what was logged here since.
 */
export async function entriesOn(client: SupabaseClient, day: IsoDay): Promise<FoodEntry[]> {
  const rows = await rowsBetween("food_entries", day, day, async () => {
    const { data, error } = await client.from("food_entries").select("*").eq("consumed_on", day).is("deleted_at", null).order("updated_at");
    if (error) throw failure(error);
    return data as KeptRow[];
  });
  return inOrder(rows);
}

/**
 * What was logged from `first` through `last`, for the partner's days; a partner that was not folded in for months
 * reads every entry since.
 */
export async function entriesBetween(client: SupabaseClient, first: IsoDay, last: IsoDay): Promise<FoodEntry[]> {
  const rows = await rowsBetween(
    "food_entries",
    first,
    last,
    async () =>
      (await allRows((from, to) =>
        client
          .from("food_entries")
          .select("*")
          .gte("consumed_on", first)
          .lte("consumed_on", last)
          .is("deleted_at", null)
          .order("id")
          .range(from, to),
      )) as KeptRow[],
  );
  return inOrder(rows);
}

/** Days with a finished workout from `first` through `last`. */
export async function workoutDaysBetween(client: SupabaseClient, first: IsoDay, last: IsoDay): Promise<IsoDay[]> {
  const rows = await allRows((from, to) =>
    client
      .from("workout_sessions")
      .select("id, performed_on")
      .gte("performed_on", first)
      .lte("performed_on", last)
      .not("ended_at", "is", null)
      .is("deleted_at", null)
      .order("id")
      .range(from, to),
  );
  return [...new Set(rows.map((row) => row.performed_on as string))];
}

/** Water is added in glasses of this size (DayViewModel.glassMl). */
export const glassMl = 250;

export async function waterOn(client: SupabaseClient, day: IsoDay): Promise<number> {
  const rows = await rowsBetween("water_entries", day, day, async () => {
    const { data, error } = await client
      .from("water_entries")
      .select("id, consumed_on, amount_ml, updated_at")
      .eq("consumed_on", day)
      .is("deleted_at", null);
    if (error) throw failure(error);
    return data as KeptRow[];
  });
  return rows.reduce((total, row) => total + Number(row.amount_ml), 0);
}

/**
 * One glass at a time, so two devices that log water add up instead of colliding (FoodDiary.addWater). Without a
 * connection the glass waits in this browser and is sent later.
 */
export async function addWater(client: SupabaseClient, userID: string, day: IsoDay, now: Date, amountMl = glassMl): Promise<void> {
  await send(client, {
    table: "water_entries",
    kind: "insert",
    row: { id: crypto.randomUUID(), user_id: userID, consumed_on: day, amount_ml: amountMl, updated_at: now.toISOString() },
  });
}

/** A deletion is a marker; the iPhone's sync removes the row there too. Without a connection it waits, as a log does. */
export async function deleteEntry(client: SupabaseClient, id: string, now: Date): Promise<void> {
  const moment = now.toISOString();
  await send(client, { table: "food_entries", kind: "update", row: { id, deleted_at: moment, updated_at: moment } });
}

/**
 * Stores what `quantity` of the product adds to the day, as it is now (FoodDiary.log); without a connection it waits in
 * this browser and is sent later. Throws when the product has no kcal or the amount cannot be worked out.
 */
export async function logProduct(
  client: SupabaseClient,
  core: FitlingCore,
  entry: { userID: string; product: Product; quantity: number; unit: QuantityUnit; meal: Meal; day: IsoDay; now: Date },
): Promise<FoodEntry> {
  const { product } = entry;
  const stored = core.logEntry({
    name: productName(core, product),
    quantity: entry.quantity,
    unit: entry.unit,
    servingSize: product.servingSize,
    per100: { kcal: product.kcal100, proteinG: product.protein100, carbsG: product.carbs100, fatG: product.fat100 },
  });
  if (!stored) throw new Error("error.server");
  const row = {
    id: crypto.randomUUID(),
    user_id: entry.userID,
    consumed_on: entry.day,
    meal: entry.meal,
    product_id: product.id,
    name: stored.name,
    quantity: stored.quantity,
    quantity_unit: entry.unit,
    kcal: stored.nutrients.kcal,
    protein_g: stored.nutrients.proteinG ?? null,
    carbs_g: stored.nutrients.carbsG ?? null,
    fat_g: stored.nutrients.fatG ?? null,
    updated_at: entry.now.toISOString(),
  };
  await send(client, { table: "food_entries", kind: "insert", row });
  // First under Recent at once, also without a connection, as on the iPhone where Recent comes from the diary on the
  // device; the next read from the server replaces the list.
  const recents = keptAnswer<Product[]>("recents");
  if (recents) {
    const { limit } = core.recentProducts({ logged: [] });
    keep("recents", [product, ...recents.filter((known) => known.id !== product.id)].slice(0, limit));
  }
  return entryFromRow(row);
}

/** The last different products the user logged, newest first (FoodDiary.recentProducts). */
export async function recentProducts(client: SupabaseClient, core: FitlingCore): Promise<Product[]> {
  return kept("recents", () => recentFromServer(client, core));
}

async function recentFromServer(client: SupabaseClient, core: FitlingCore): Promise<Product[]> {
  const { data, error } = await client
    .from("food_entries")
    .select("product_id, updated_at")
    .not("product_id", "is", null)
    .is("deleted_at", null)
    .order("updated_at", { ascending: false })
    .limit(200);
  if (error) throw failure(error);
  const { ids, limit } = core.recentProducts({
    logged: (data as Row[]).map((row) => ({ productID: row.product_id as string, updatedAtMs: Date.parse(row.updated_at as string) })),
  });
  return (await productsByID(client, ids)).slice(0, limit);
}

async function favoriteRows(client: SupabaseClient, productID?: string): Promise<Row[]> {
  const query = client.from("favorite_products").select("id, product_id").is("deleted_at", null);
  const { data, error } = await (productID ? query.eq("product_id", productID) : query);
  if (error) throw failure(error);
  return data as Row[];
}

export async function favoriteProducts(client: SupabaseClient): Promise<Product[]> {
  return kept("favorites", async () => {
    const ids = [...new Set((await favoriteRows(client)).map((row) => row.product_id as string))];
    return productsByID(client, ids);
  });
}

export async function isFavorite(client: SupabaseClient, productID: string): Promise<boolean> {
  const ids = await kept("favoriteIDs", async () => (await favoriteRows(client)).map((row) => row.product_id as string));
  return ids.includes(productID);
}

/** On: one row; off: every row for the product gets deleted_at (FoodDiary.setFavorite). */
export async function setFavorite(client: SupabaseClient, userID: string, productID: string, favorite: boolean, now: Date): Promise<void> {
  const existing = await favoriteRows(client, productID);
  const moment = now.toISOString();
  const { error } = favorite
    ? existing.length > 0
      ? { error: null }
      : await client.from("favorite_products").insert({ id: crypto.randomUUID(), user_id: userID, product_id: productID, updated_at: moment })
    : await client
        .from("favorite_products")
        .update({ deleted_at: moment, updated_at: moment })
        .in(
          "id",
          existing.map((row) => row.id as string),
        );
  if (error) throw failure(error);
}
