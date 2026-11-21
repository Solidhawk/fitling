#!/usr/bin/env node
// Maakt uit supabase/seed/recipes.json de receptencatalogus van de app (Fitling/Resources/RecipeCatalog.json)
// en de seed voor de server (supabase/seed/recipes.sql). Energie en macro's per portie worden uitgerekend
// uit de ingrediënten en de USDA-tabel (supabase/seed/usda-sr-legacy.json), nooit met de hand ingevuld.
// Met --check faalt het script als een van beide bestanden verouderd is.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const LANGUAGES = ['nl', 'en', 'de'];
export const UNITS = ['g', 'ml', 'piece', 'tbsp', 'tsp'];
export const AISLES = ['produce', 'bakery', 'meat_fish', 'dairy', 'frozen', 'pantry', 'drinks', 'household', 'other'];
export const SLOTS = ['breakfast', 'lunch', 'dinner', 'snack'];
const FREE_LICENCES = /^(CC0|Public domain|CC BY(-SA)? [0-9.]+)$/;

const round1 = (value) => Math.round(value * 10) / 10;
const literal = (text) => `'${String(text).replaceAll("'", "''")}'`;
const json = (value) => `${literal(JSON.stringify(value))}::jsonb`;
const textArray = (items) => (items.length === 0 ? `'{}'::text[]` : `array[${items.map(literal).join(', ')}]::text[]`);

/** Energy and macros per serving from the ingredients. */
export function nutrition(recipe, usda) {
  const total = { kcal: 0, protein: 0, carbs: 0, fat: 0 };
  for (const ingredient of recipe.ingredients) {
    const food = usda[String(ingredient.fdcId)];
    for (const key of Object.keys(total)) total[key] += (food[key] * ingredient.grams) / 100;
  }
  return Object.fromEntries(Object.entries(total).map(([key, value]) => [key, round1(value / recipe.servings)]));
}

/** Problems with the recipes, empty when they are consistent. */
export function validate(recipes, usda, photos) {
  const problems = [];
  const ids = new Set();
  const unique = (id, what) => {
    if (ids.has(id)) problems.push(`${what}: id ${id} komt twee keer voor`);
    ids.add(id);
  };
  for (const recipe of recipes) {
    const what = `recept ${recipe.slug}`;
    unique(recipe.id, what);
    for (const language of LANGUAGES) {
      if (!recipe.title?.[language]) problems.push(`${what}: geen titel in ${language}`);
      if (!(recipe.steps?.[language]?.length > 0)) problems.push(`${what}: geen stappen in ${language}`);
      if (recipe.steps?.[language]?.length !== recipe.steps?.nl?.length) problems.push(`${what}: niet evenveel stappen in ${language}`);
    }
    if (!(recipe.servings >= 1 && recipe.servings <= 20)) problems.push(`${what}: ${recipe.servings} porties`);
    if (!(recipe.cookMinutes >= 0 && recipe.cookMinutes <= 600)) problems.push(`${what}: ${recipe.cookMinutes} minuten`);
    if (recipe.mealSlots.length === 0 || recipe.mealSlots.some((slot) => !SLOTS.includes(slot))) problems.push(`${what}: maaltijden ${recipe.mealSlots}`);
    const photo = photos[recipe.photo];
    if (!photo) problems.push(`${what}: geen foto`);
    else if (!FREE_LICENCES.test(photo.licence)) problems.push(`${what}: licentie ${photo.licence} is niet vrij`);
    else if (!photo.author || !photo.page) problems.push(`${what}: maker of bron van de foto ontbreekt`);
    for (const ingredient of recipe.ingredients) {
      const where = `${what}, ${ingredient.name?.nl}`;
      unique(ingredient.id, where);
      for (const language of LANGUAGES) if (!ingredient.name?.[language]) problems.push(`${where}: geen naam in ${language}`);
      if (!UNITS.includes(ingredient.unit)) problems.push(`${where}: eenheid ${ingredient.unit}`);
      if (!AISLES.includes(ingredient.aisle)) problems.push(`${where}: schap ${ingredient.aisle}`);
      if (!(ingredient.quantity > 0 && ingredient.grams > 0)) problems.push(`${where}: hoeveelheid ${ingredient.quantity}, ${ingredient.grams} g`);
      if (['g', 'ml'].includes(ingredient.unit) && ingredient.quantity !== ingredient.grams) problems.push(`${where}: ${ingredient.quantity} ${ingredient.unit} is niet ${ingredient.grams} g`);
      if (!usda[String(ingredient.fdcId)]) problems.push(`${where}: USDA ${ingredient.fdcId} ontbreekt in de tabel`);
    }
  }
  // De boodschappenlijst telt hetzelfde ingrediënt op; grammen, milliliters en stuks tellen niet bij elkaar op,
  // eet- en theelepels wel.
  const kinds = new Map();
  for (const recipe of recipes) {
    for (const ingredient of recipe.ingredients) {
      const name = ingredient.name?.nl?.trim().toLowerCase();
      if (!name) continue;
      const kind = ['tbsp', 'tsp'].includes(ingredient.unit) ? 'lepels' : ingredient.unit;
      if (!kinds.has(name)) kinds.set(name, new Map());
      kinds.get(name).set(kind, [...(kinds.get(name).get(kind) ?? []), recipe.slug]);
    }
  }
  for (const [name, byKind] of kinds) {
    if (byKind.size > 1) {
      const where = [...byKind].map(([kind, slugs]) => `${kind} in ${slugs.join(', ')}`).join('; ');
      problems.push(`ingrediënt ${name} staat in verschillende eenheden: ${where}`);
    }
  }
  return problems;
}

export function catalog(source, usda, photos) {
  return {
    version: source.version,
    recipes: source.recipes.map((recipe) => {
      const values = nutrition(recipe, usda);
      const photo = photos[recipe.photo];
      return {
        id: recipe.id,
        title: recipe.title,
        steps: recipe.steps,
        servings: recipe.servings,
        cookMinutes: recipe.cookMinutes,
        kcalPerServing: values.kcal,
        proteinGPerServing: values.protein,
        carbsGPerServing: values.carbs,
        fatGPerServing: values.fat,
        keepsWell: recipe.keepsWell,
        mealSlots: recipe.mealSlots,
        tags: recipe.tags,
        photoCredit: { author: photo.author, licence: photo.licence, page: photo.page },
        ingredients: recipe.ingredients.map((ingredient, position) => ({
          id: ingredient.id, name: ingredient.name, quantity: ingredient.quantity, unit: ingredient.unit, aisle: ingredient.aisle, position,
        })),
      };
    }),
  };
}

export function seedSQL(built) {
  const updatedAt = `'2026-11-19T00:00:00Z'::timestamptz + interval '${built.version - 1} seconds'`;
  const lines = [
    '-- Gemaakt door scripts/recipe-seed.mjs uit supabase/seed/recipes.json. Niet met de hand aanpassen.',
    '-- Zet de gedeelde recepten en hun ingrediënten neer; een tweede keer werkt ze bij.',
    'begin;',
  ];
  for (const r of built.recipes) {
    lines.push(
      '',
      'insert into public.recipes (id, owner_id, title, steps, servings, cook_minutes, kcal_per_serving, protein_g_per_serving, carbs_g_per_serving, fat_g_per_serving, keeps_well, meal_slots, tags, updated_at)',
      `values (${literal(r.id)}, null, ${json(r.title)}, ${json(r.steps)}, ${r.servings}, ${r.cookMinutes}, ${r.kcalPerServing}, ${r.proteinGPerServing}, ` +
        `${r.carbsGPerServing}, ${r.fatGPerServing}, ${r.keepsWell}, ${textArray(r.mealSlots)}, ${textArray(r.tags)}, ${updatedAt})`,
      'on conflict (id) do update set title = excluded.title, steps = excluded.steps, servings = excluded.servings, cook_minutes = excluded.cook_minutes, ' +
        'kcal_per_serving = excluded.kcal_per_serving, protein_g_per_serving = excluded.protein_g_per_serving, carbs_g_per_serving = excluded.carbs_g_per_serving, ' +
        'fat_g_per_serving = excluded.fat_g_per_serving, keeps_well = excluded.keeps_well, meal_slots = excluded.meal_slots, tags = excluded.tags, updated_at = excluded.updated_at;',
    );
    for (const i of r.ingredients) {
      lines.push(
        'insert into public.recipe_ingredients (id, recipe_id, owner_id, name, quantity, unit, aisle, position, updated_at)',
        `values (${literal(i.id)}, ${literal(r.id)}, null, ${json(i.name)}, ${i.quantity}, ${literal(i.unit)}, ${literal(i.aisle)}, ${i.position}, ${updatedAt})`,
        'on conflict (id) do update set name = excluded.name, quantity = excluded.quantity, unit = excluded.unit, aisle = excluded.aisle, ' +
          'position = excluded.position, updated_at = excluded.updated_at;',
      );
    }
  }
  lines.push('', 'commit;', '');
  return lines.join('\n');
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..');
  const read = (path) => JSON.parse(readFileSync(join(root, path), 'utf8'));
  const source = read('supabase/seed/recipes.json');
  const usda = read('supabase/seed/usda-sr-legacy.json').perHundredGrams;
  const photos = read('supabase/seed/recipe-photos.json');
  const problems = validate(source.recipes, usda, photos);
  for (const problem of problems) console.error(`error: ${problem}`);
  if (problems.length > 0) process.exit(1);
  const built = catalog(source, usda, photos);
  const outputs = {
    'Fitling/Resources/RecipeCatalog.json': JSON.stringify(built, null, 2) + '\n',
    'supabase/seed/recipes.sql': seedSQL(built),
  };
  if (process.argv.includes('--check')) {
    for (const [path, content] of Object.entries(outputs)) {
      let current = '';
      try { current = readFileSync(join(root, path), 'utf8').replaceAll('\r\n', '\n'); } catch { /* ontbreekt */ }
      if (current !== content) {
        console.error(`error: ${path} is verouderd; draai node scripts/recipe-seed.mjs`);
        process.exit(1);
      }
    }
    console.log(`recipe-seed: up to date (${built.recipes.length} recipes)`);
  } else {
    for (const [path, content] of Object.entries(outputs)) writeFileSync(join(root, path), content);
    console.log(`recipe-seed: wrote ${Object.keys(outputs).join(', ')}`);
  }
}
