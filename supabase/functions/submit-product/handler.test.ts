import { assertEquals } from '@std/assert';
import { type Deps, handle, type SharedRow, type Submitted } from './handler.ts';

const user = { id: '00000000-0000-4000-8000-000000000001' };

// What the database decides (made, kept, corrected) is tested in supabase/tests/submit_product_test.sql.
function deps(created = true) {
  const submitted: { userID: string; payload: Submitted; row: SharedRow }[] = [];
  const log: string[] = [];
  let allowed = true;
  const d: Deps = {
    getUser: (token) => Promise.resolve(token === 'good' ? user : null),
    consumeRateLimit: () => Promise.resolve(allowed),
    submit: (userID, payload, row) => {
      submitted.push({ userID, payload, row });
      return Promise.resolve({ productID: 'product-1', created });
    },
    log: (message) => log.push(message),
  };
  return { d, submitted, log, refuse: () => (allowed = false) };
}

const product = {
  gtin: '8712100849084',
  name: "  Oma's Appeltaart ",
  brand: 'Bakkerij Jansen',
  language: 'nl',
  quantityUnit: 'g',
  servingSize: 120,
  kcal: 280.44,
  protein: 3.2,
  carbs: 38,
  sugars: 21,
  fat: 12.5,
  saturatedFat: 6,
  fiber: 1.8,
  salt: 0.3,
};

function call(d: Deps, body: unknown, token = 'good'): Promise<Response> {
  return handle(
    new Request('http://localhost/submit-product', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: typeof body === 'string' ? body : JSON.stringify(body),
    }),
    d,
  );
}

Deno.test('only a signed-in user may share a product', async () => {
  const { d, submitted } = deps();
  assertEquals((await call(d, product, 'bad')).status, 401);
  assertEquals(submitted.length, 0);
});

Deno.test('a product nobody shared yet is sent as the shared row for its barcode, unverified', async () => {
  const { d, submitted } = deps();
  const response = await call(d, product);
  assertEquals(response.status, 201);
  assertEquals(await response.json(), { productID: 'product-1', created: true });
  assertEquals(submitted[0].userID, user.id);
  assertEquals(submitted[0].row, {
    source: 'user',
    gtin: '8712100849084',
    name: { nl: "Oma's Appeltaart" },
    brand: 'Bakkerij Jansen',
    search_name: "oma's appeltaart bakkerij jansen",
    quantity_unit: 'g',
    serving_size: 120,
    kcal_100: 280.4,
    protein_100: 3.2,
    carbs_100: 38,
    sugars_100: 21,
    fat_100: 12.5,
    saturated_fat_100: 6,
    fiber_100: 1.8,
    salt_100: 0.3,
    is_verified: false,
  });
  // The submission is kept as it was sent.
  assertEquals(submitted[0].payload, product);
});

Deno.test('a barcode that already has its shared row answers with that row', async () => {
  const { d } = deps(false);
  const response = await call(d, product);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { productID: 'product-1', created: false });
});

Deno.test('the submission keeps only the fields the app sends', async () => {
  const { d, submitted } = deps();
  await call(d, { ...product, email: 'a@example.test', nested: { deep: true }, kcal: 280 });
  assertEquals(Object.keys(submitted[0].payload).includes('email'), false);
  assertEquals(Object.keys(submitted[0].payload).includes('nested'), false);
  assertEquals(submitted[0].payload.kcal, 280);
});

Deno.test('the barcode must be real, the energy there, the name and brand of a sensible length', async () => {
  const { d, submitted } = deps();
  assertEquals((await call(d, { ...product, gtin: '8712100849085' })).status, 400);
  assertEquals((await call(d, { ...product, kcal: 950 })).status, 400);
  assertEquals((await call(d, { ...product, kcal: undefined })).status, 400);
  assertEquals((await call(d, { ...product, name: '   ' })).status, 400);
  assertEquals((await call(d, { ...product, name: 'a'.repeat(201) })).status, 400);
  assertEquals((await call(d, { ...product, brand: 'b'.repeat(101) })).status, 400);
  assertEquals((await call(d, '{not json')).status, 400);
  assertEquals((await call(d, [product])).status, 400);
  assertEquals(submitted.length, 0);
  // Two hundred characters, whatever the letters: as Swift counts them.
  assertEquals((await call(d, { ...product, name: 'é'.repeat(200) })).status, 201);
});

Deno.test('a value that cannot be true per 100 g is left out, as for Open Food Facts', async () => {
  const { d, submitted } = deps();
  await call(d, {
    ...product,
    protein: 120,
    salt: -1,
    servingSize: 0.001,
    quantityUnit: 'litre',
    language: 'xx',
    brand: '  ',
  });
  const row = submitted[0].row;
  assertEquals(row.protein_100, null);
  assertEquals(row.salt_100, null);
  // 0.001 rounds to 0, which serving_size > 0 refuses.
  assertEquals(row.serving_size, null);
  assertEquals(row.quantity_unit, 'g');
  assertEquals(row.name, { nl: "Oma's Appeltaart" });
  assertEquals(row.brand, null);
  await call(d, { ...product, servingSize: 99_999.999 });
  // Rounds to 100000, more than numeric(7,2) holds.
  assertEquals(submitted[1].row.serving_size, null);
  await call(d, { ...product, kcal: 899.96 });
  // Rounds to 900.0, the highest kcal_100 allows.
  assertEquals(submitted[2].row.kcal_100, 900);
});

Deno.test('sharing is limited per hour', async () => {
  const { d, refuse, submitted } = deps();
  refuse();
  assertEquals((await call(d, product)).status, 429);
  assertEquals(submitted.length, 0);
});

Deno.test('the web app may ask first from its own origin, and sees a server error as one', async () => {
  const { d, log } = deps();
  const preflight = await handle(new Request('http://localhost/submit-product', { method: 'OPTIONS' }), d);
  assertEquals(preflight.status, 204);
  assertEquals(preflight.headers.get('Access-Control-Allow-Origin'), '*');
  d.submit = () => Promise.reject(new Error('database unavailable'));
  const failed = await call(d, product);
  assertEquals(failed.status, 500);
  assertEquals(failed.headers.get('Access-Control-Allow-Origin'), '*');
  assertEquals(log.length, 1);
});
