import { readFileSync } from "node:fs";
import { createClient } from "@supabase/supabase-js";
import type { Page } from "@playwright/test";

// Read as a file: Node only imports JSON with an import attribute, which Playwright's loader does not pass on.
const strings = JSON.parse(readFileSync(new URL("../src/generated/strings.json", import.meta.url), "utf8")) as {
  nl: Record<string, string | { one: string; other: string }>;
};

// Only against the local Supabase that CI starts; its keys are the public development keys of `supabase start`.
const url = process.env.VITE_SUPABASE_URL ?? "";
const service = process.env.LOCAL_SUPABASE_SERVICE_KEY ?? "";
export const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });

/** The Dutch text of a key, as the browser in the tests shows it (locale nl-NL); a plural in its "other" form. */
export function nl(key: string): string {
  const entry = strings.nl[key];
  return typeof entry === "string" ? entry : (entry?.other ?? key);
}

/** The Dutch text of a plural key for `count`, with the number filled in, as the app chooses it. */
export function nlCount(key: string, count: number): string {
  const entry = strings.nl[key];
  const text = typeof entry === "string" ? entry : new Intl.PluralRules("nl").select(count) === "one" ? entry.one : entry.other;
  return text.replace("%lld", String(count));
}

export const password = "lang-genoeg-wachtwoord-1";

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * A confirmed user, optionally with the profile of NutritionEngineTests (2760 kcal) and an owl as partner, so a
 * test can start at any screen.
 */
export async function createUser(options: { profile?: boolean; creature?: boolean } = {}) {
  const email = `e2e-${crypto.randomUUID()}@fitling.test`;
  const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (created.error) throw created.error;
  const id = created.data.user.id;
  const now = new Date().toISOString();
  if (options.profile) {
    const profile = await admin.from("profiles").insert({
      id,
      health_consent_at: now,
      health_consent_version: 1,
      birth_date: "1996-01-10",
      sex: "male",
      height_cm: 180,
      weight_kg: 80,
      activity_level: "moderate",
      goal: "maintain",
      kcal_target: 2760,
      protein_target_g: 128,
      carbs_target_g: 389,
      fat_target_g: 77,
      updated_at: now,
    });
    if (profile.error) throw profile.error;
    const period = await admin.from("target_history").insert({
      user_id: id,
      effective_on: today(),
      kcal_target: 2760,
      protein_target_g: 128,
      carbs_target_g: 389,
      fat_target_g: 77,
      updated_at: now,
    });
    if (period.error) throw period.error;
  }
  if (options.creature) {
    const creature = await admin.from("creatures").insert({
      user_id: id,
      species: "owl",
      name: "Uiltje",
      color_index: 0,
      tone: "sweet",
      created_on: today(),
      body_shape: 0.3,
      updated_at: now,
    });
    if (creature.error) throw creature.error;
  }
  return { id, email };
}

export async function signIn(page: Page, email: string) {
  await page.goto("./");
  await page.getByTestId("welcome.email").click();
  // By field type, not by label: the tests in en-US see English labels.
  await page.locator('input[type="email"]').fill(email);
  await page.locator('input[type="password"]').fill(password);
  await page.getByTestId("auth.submit").click();
}

/** The confirmation link of the newest mail to `email`, from the local mail catcher (Mailpit). */
export async function confirmationLink(email: string): Promise<string> {
  for (let attempt = 0; attempt < 20; attempt++) {
    const search = await fetch(`http://127.0.0.1:54324/api/v1/search?query=${encodeURIComponent(`to:${email}`)}`).then((r) => r.json());
    const message = search.messages?.[0];
    if (message) {
      const body = await fetch(`http://127.0.0.1:54324/api/v1/message/${message.ID}`).then((r) => r.json());
      const link = /https?:\/\/[^\s"<>]+\/auth\/v1\/verify\?[^\s"<>]+/.exec(String(body.Text ?? body.HTML))?.[0];
      if (link) return link.replace(/&amp;/g, "&");
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`no confirmation mail for ${email}`);
}

/**
 * A shared product, as the Edge Function lookup-product stores it; users cannot write those. The name gets a unique
 * word, so a search in one test does not find another test's products.
 */
export async function sharedProduct(name: string, values: Record<string, unknown> = {}) {
  const unique = `${name} ${crypto.randomUUID().slice(0, 8)}`;
  const row = {
    id: crypto.randomUUID(),
    source: "off",
    name: { nl: unique },
    search_name: unique.toLowerCase(),
    quantity_unit: "g",
    kcal_100: 250,
    protein_100: 10,
    carbs_100: 30,
    fat_100: 8,
    fetched_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    ...values,
  };
  const { error } = await admin.from("products").insert(row);
  if (error) throw error;
  return { id: row.id, name: unique };
}

/** A food entry stored as the iPhone would have synced it. */
export async function foodEntry(userID: string, values: Record<string, unknown>) {
  const { error } = await admin.from("food_entries").insert({
    id: crypto.randomUUID(),
    user_id: userID,
    meal: "breakfast",
    name: "Volkorenbrood",
    quantity: 100,
    quantity_unit: "g",
    kcal: 250,
    protein_g: 10,
    carbs_g: 40,
    fat_g: 3,
    updated_at: new Date().toISOString(),
    ...values,
  });
  if (error) throw error;
}

/** Today in the browser's time zone, as Postgres writes a date. */
export function localDay(date = new Date()): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

/** A fresh, valid EAN-13 (with its GS1 check digit), so tests running side by side never share a barcode. */
export function ean13(): string {
  const digits = Array.from({ length: 12 }, (_, index) => (index === 0 ? 2 : Math.floor(Math.random() * 10)));
  const sum = digits.reduce((total, digit, index) => total + digit * (index % 2 === 0 ? 1 : 3), 0);
  return [...digits, (10 - (sum % 10)) % 10].join("");
}
