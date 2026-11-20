import { assertEquals } from '@std/assert';
import { isConsistent, isValidGtin, kcalFromKilojoules, normalizeOffProduct } from './normalize.ts';

const fetchedAt = new Date('2026-11-19T12:00:00Z');
const fixture = JSON.parse(await Deno.readTextFile(new URL('./fixtures/off-8712100849084.json', import.meta.url)));

function product(overrides: Record<string, unknown> = {}, nutriments: Record<string, unknown> = {}) {
  return {
    lc: 'nl',
    product_name_nl: 'Volkorenbrood',
    brands: 'Bakker',
    nutriments: {
      'energy-kcal_100g': 250,
      proteins_100g: 10,
      carbohydrates_100g: 40,
      fat_100g: 5,
      ...nutriments,
    },
    ...overrides,
  };
}

Deno.test('a real Open Food Facts answer becomes a shared product row', () => {
  const row = normalizeOffProduct(fixture.product, '8712100849084', fetchedAt);
  assertEquals(row, {
    source: 'off',
    source_id: '8712100849084',
    gtin: '8712100849084',
    name: { de: 'Double Caramel' },
    brand: 'Magnum, Unilever',
    search_name: 'double caramel magnum, unilever',
    quantity_unit: 'ml',
    serving_size: 88,
    kcal_100: 338,
    protein_100: 3.2,
    carbs_100: 36,
    sugars_100: 33,
    fat_100: 20,
    saturated_fat_100: 14,
    fiber_100: null,
    salt_100: 0.17,
    image_url: 'https://images.openfoodfacts.org/images/products/871/210/084/9084/front_en.100.400.jpg',
    is_verified: true,
    fetched_at: '2026-11-19T12:00:00.000Z',
  });
});

Deno.test('the name in the product language is used when no nl, en or de name exists', () => {
  const row = normalizeOffProduct({ lc: 'fr', product_name: 'Pain complet', nutriments: {} }, '87654321', fetchedAt);
  assertEquals(row?.name, { fr: 'Pain complet' });
  assertEquals(row?.search_name, 'pain complet');
});

Deno.test('a product without any name is not stored', () => {
  assertEquals(normalizeOffProduct({ lc: 'nl', product_name: ' ', nutriments: {} }, '87654321', fetchedAt), null);
});

Deno.test('converts kilojoules when kcal is missing', () => {
  const row = normalizeOffProduct(
    product({}, { 'energy-kcal_100g': undefined, energy_100g: 2092 }),
    '87654321',
    fetchedAt,
  );
  assertEquals(row?.kcal_100, 500);
  assertEquals(kcalFromKilojoules(1046), 250);
});

Deno.test('leaves missing nutrients empty instead of zero', () => {
  const row = normalizeOffProduct(product({}, { proteins_100g: undefined, fat_100g: '' }), '87654321', fetchedAt);
  assertEquals(row?.protein_100, null);
  assertEquals(row?.fat_100, null);
  assertEquals(row?.carbs_100, 40);
});

Deno.test('drops values outside their limits', () => {
  const row = normalizeOffProduct(
    product({}, { proteins_100g: 120, 'energy-kcal_100g': 950, salt_100g: -1 }),
    '87654321',
    fetchedAt,
  );
  assertEquals(row?.protein_100, null);
  assertEquals(row?.kcal_100, null);
  assertEquals(row?.salt_100, null);
});

Deno.test('marks an inconsistent label as unverified', () => {
  // 4 × 10 + 4 × 40 + 9 × 5 = 245: fits 250.
  assertEquals(normalizeOffProduct(product(), '87654321', fetchedAt)?.is_verified, true);
  // The macros give 245 kcal, the label says 100.
  assertEquals(
    normalizeOffProduct(product({}, { 'energy-kcal_100g': 100 }), '87654321', fetchedAt)?.is_verified,
    false,
  );
  // Without all three macros the label cannot be checked.
  assertEquals(normalizeOffProduct(product({}, { fat_100g: undefined }), '87654321', fetchedAt)?.is_verified, false);
});

Deno.test('the consistency rule matches FoodMath', () => {
  assertEquals(isConsistent(600, 25, 12, 50), true);
  assertEquals(isConsistent(250, 10, 30, 10), true);
  assertEquals(isConsistent(100, 10, 50, 20), false);
  assertEquals(isConsistent(500, 10, 30, 10), false);
  assertEquals(isConsistent(20, 1, 3, 1.5), true);
});

Deno.test('millilitres when the serving or the quantity unit is a volume', () => {
  assertEquals(normalizeOffProduct(product({ serving_size: '250 ml' }), '87654321', fetchedAt)?.quantity_unit, 'ml');
  assertEquals(
    normalizeOffProduct(product({ product_quantity_unit: 'cl' }), '87654321', fetchedAt)?.quantity_unit,
    'ml',
  );
  assertEquals(
    normalizeOffProduct(product({ serving_size: '2 slices (70 g)' }), '87654321', fetchedAt)?.quantity_unit,
    'g',
  );
});

Deno.test('rejects a wrong check digit', () => {
  assertEquals(isValidGtin('4006381333931'), true);
  assertEquals(isValidGtin('4006381333932'), false);
  assertEquals(isValidGtin('96385074'), true);
  assertEquals(isValidGtin('036000291452'), false);
  assertEquals(isValidGtin('0036000291452'), true);
  assertEquals(isValidGtin('abc'), false);
});
