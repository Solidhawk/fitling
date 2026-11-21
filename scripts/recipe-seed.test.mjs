import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { validate, nutrition, catalog, seedSQL } from './recipe-seed.mjs';

const read = (path) => JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), 'utf8'));
const source = read('supabase/seed/recipes.json');
const usda = read('supabase/seed/usda-sr-legacy.json').perHundredGrams;
const photos = read('supabase/seed/recipe-photos.json');
const copy = () => structuredClone(source.recipes);

test('de recepten kloppen', () => {
  assert.deepEqual(validate(source.recipes, usda, photos), []);
});

test('de energie per portie komt uit de ingrediënten', () => {
  const recipe = {
    servings: 2,
    ingredients: [{ fdcId: 171413, grams: 10 }, { fdcId: 173944, grams: 100 }],
  };
  const oil = usda['171413'];
  const banana = usda['173944'];
  assert.equal(nutrition(recipe, usda).kcal, Math.round(((oil.kcal * 10) / 100 + banana.kcal) / 2 * 10) / 10);
});

test('een foto zonder vrije licentie valt op', () => {
  const unfree = structuredClone(photos);
  unfree[source.recipes[0].photo].licence = 'All rights reserved';
  assert.match(validate(source.recipes, usda, unfree).join('\n'), /niet vrij/);
});

test('een ingrediënt zonder voedingswaarden valt op', () => {
  const broken = copy();
  broken[0].ingredients[0].fdcId = 1;
  assert.match(validate(broken, usda, photos).join('\n'), /ontbreekt in de tabel/);
});

test('grammen en milliliters moeten overeenkomen met het gewicht', () => {
  const broken = copy();
  const ingredient = broken.flatMap((r) => r.ingredients).find((i) => i.unit === 'g');
  ingredient.grams += 1;
  assert.match(validate(broken, usda, photos).join('\n'), /is niet/);
});

// Grammen en stuks tellen op de boodschappenlijst niet op, dus dan staat het er twee keer (UNFORGET S24).
test('een ingrediënt in grammen in het ene recept en in stuks in het andere valt op', () => {
  const broken = copy();
  const grams = broken[0].ingredients.find((i) => i.unit === 'g');
  broken[1].ingredients.push({ ...structuredClone(grams), id: '00000000-0000-0000-0000-000000000001', unit: 'piece', quantity: 1 });
  assert.match(validate(broken, usda, photos).join('\n'), /verschillende eenheden/);
});

test('elke regel van de seed heeft een even aantal aanhalingstekens', () => {
  const sql = seedSQL(catalog(source, usda, photos));
  for (const line of sql.split('\n').filter((l) => !l.startsWith('--'))) {
    assert.equal((line.match(/'/g) ?? []).length % 2, 0, line.slice(0, 80));
  }
});
