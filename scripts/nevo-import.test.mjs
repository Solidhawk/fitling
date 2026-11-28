import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { nevoID, parseNevo, productRow, REFERENCE, toSql } from './nevo-import.mjs';

// Invented foods in the layout of the NEVO-online table (UNFORGET S15); the real table stays out of git.
const fixture = readFileSync(new URL('fixtures/nevo-test.csv', import.meta.url), 'utf8');
const strings = JSON.parse(readFileSync(new URL('../Fitling/Resources/Localizable.xcstrings', import.meta.url), 'utf8'));

test('readsEveryFoodByColumnName', () => {
  const foods = parseNevo(fixture);
  assert.equal(foods.length, 3);
  assert.equal(foods[0]['NEVO-code'], '9001');
  assert.equal(foods[0]['Voedingsmiddelgroep'], 'Testgroep');
  assert.equal(foods[1]['Voedingsmiddelnaam/Dutch food name'], "Testdrank O'Neill");
});

test('aProductHasTheValuesOfNevoUnchanged', () => {
  const [apple] = parseNevo(fixture);
  assert.deepEqual(productRow(apple), {
    id: nevoID('9001'),
    source: 'nevo',
    source_id: '9001',
    name: { nl: 'Testappel z schil', en: 'Test apple without skin' },
    search_name: 'testappel z schil test apple without skin testappeltje',
    quantity_unit: 'g',
    kcal_100: 52,
    protein_100: 0.3,
    carbs_100: 12.4,
    sugars_100: 10,
    fat_100: 0.2,
    saturated_fat_100: 0,
    fiber_100: 2.1,
    // Salt from sodium with the factor of EU regulation 1169/2011: 380 mg × 2.5.
    salt_100: 0.95,
    is_verified: true,
  });
});

test('anEmptyValueIsUnknownAndADrinkIsPer100Ml', () => {
  const drink = productRow(parseNevo(fixture)[1]);
  assert.equal(drink.quantity_unit, 'ml');
  assert.equal(drink.sugars_100, null);
  assert.equal(drink.fiber_100, null);
  assert.equal(drink.salt_100, null);
  assert.equal(drink.protein_100, 0);
});

test('theSearchNameHasNoAccents', () => {
  assert.equal(productRow(parseNevo(fixture)[2]).search_name, 'testcreme brulee test creme brulee');
});

test('aCodeAlwaysGetsTheSameID', () => {
  assert.equal(nevoID('9001'), nevoID('9001'));
  assert.notEqual(nevoID('9001'), nevoID('9002'));
  assert.match(nevoID('9001'), /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test('anotherVersionOfNevoIsRefused', () => {
  const other = fixture.replaceAll('NEVO-Online 2025 9.0', 'NEVO-Online 2027 10.0');
  assert.throws(() => productRow(parseNevo(other)[0]), /NEVO-Online 2027 10\.0/);
});

test('theSqlUpsertsAndRetiresWhatIsNoLongerInNevo', () => {
  const sql = toSql(parseNevo(fixture).map(productRow));
  assert.match(sql, /^begin;$/m);
  assert.match(sql, /on conflict \(id\) do update set/);
  // A food that comes back in a newer table is no longer retired.
  assert.match(sql, /deleted_at = null/);
  assert.match(sql, /source_id <> all \(array\['9001', '9002', '9003'\]\)/);
  // The name goes into a quoted jsonb literal, so a quote in it is doubled.
  assert.ok(sql.includes(`"Testdrank O''Neill"`), 'the quote in the name is not escaped');
  assert.match(sql, /^commit;$/m);
});

test('aboutNamesNevoAsItsTermsAsk', () => {
  const nevo = strings.strings['account.about.nevo'];
  assert.ok(nevo, 'no account.about.nevo');
  for (const language of ['nl', 'en', 'de']) {
    assert.ok(nevo.localizations[language].stringUnit.value.includes(REFERENCE), `${language} lacks "${REFERENCE}"`);
  }
});
