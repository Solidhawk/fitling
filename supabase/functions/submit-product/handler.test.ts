import { assertEquals } from '@std/assert';
import { type Deps, handle, type SharedRow } from './handler.ts';

const user = { id: '00000000-0000-4000-8000-000000000001' };

function deps(existing: { id: string } | null = null) {
  const submissions: { userID: string; gtin: string; payload: unknown }[] = [];
  const inserted: SharedRow[] = [];
  const accepted: { submissionID: string; productID: string }[] = [];
  let allowed = true;
  const d: Deps = {
    getUser: (token) => Promise.resolve(token === 'good' ? user : null),
    consumeRateLimit: () => Promise.resolve(allowed),
    storeSubmission: (userID, gtin, payload) => {
      submissions.push({ userID, gtin, payload });
      return Promise.resolve(`submission-${submissions.length}`);
    },
    findShared: () => Promise.resolve(existing),
    insertShared: (row) => {
      inserted.push(row);
      return Promise.resolve('product-1');
    },
    markAccepted: (submissionID, productID) => {
      accepted.push({ submissionID, productID });
      return Promise.resolve();
    },
  };
  return { d, submissions, inserted, accepted, refuse: () => (allowed = false) };
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
      body: JSON.stringify(body),
    }),
    d,
  );
}

Deno.test('only a signed-in user may share a product', async () => {
  const { d, submissions } = deps();
  assertEquals((await call(d, product, 'bad')).status, 401);
  assertEquals(submissions.length, 0);
});

Deno.test('a product nobody shared yet becomes the shared row for its barcode, unverified', async () => {
  const { d, submissions, inserted, accepted } = deps();
  const response = await call(d, product);
  assertEquals(response.status, 201);
  assertEquals(await response.json(), { productID: 'product-1', created: true });
  assertEquals(inserted, [{
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
  }]);
  // The submission is kept as it was sent, with who sent it.
  assertEquals(submissions, [{ userID: user.id, gtin: '8712100849084', payload: product }]);
  assertEquals(accepted, [{ submissionID: 'submission-1', productID: 'product-1' }]);
});

Deno.test('a barcode that already has a shared row keeps it; the submission waits', async () => {
  const { d, submissions, inserted, accepted } = deps({ id: 'product-off' });
  const response = await call(d, product);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { productID: 'product-off', created: false });
  assertEquals(inserted, []);
  assertEquals(accepted, []);
  assertEquals(submissions.length, 1);
});

Deno.test('two users at once: the second finds the row the first made', async () => {
  const { d, inserted } = deps();
  let found: { id: string } | null = null;
  d.findShared = () => Promise.resolve(found);
  d.insertShared = (row) => {
    inserted.push(row);
    // The unique index refused it: someone was just ahead.
    found = { id: 'product-first' };
    return Promise.resolve(null);
  };
  const response = await call(d, product);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { productID: 'product-first', created: false });
});

Deno.test('the barcode must be a real one and the energy must be there', async () => {
  const { d, submissions } = deps();
  assertEquals((await call(d, { ...product, gtin: '8712100849085' })).status, 400);
  assertEquals((await call(d, { ...product, kcal: 950 })).status, 400);
  assertEquals((await call(d, { ...product, kcal: undefined })).status, 400);
  assertEquals((await call(d, { ...product, name: '   ' })).status, 400);
  assertEquals((await call(d, 'not json')).status, 400);
  assertEquals(submissions.length, 0);
});

Deno.test('a value that cannot be true per 100 g is left out, as for Open Food Facts', async () => {
  const { d, inserted } = deps();
  await call(d, { ...product, protein: 120, salt: -1, servingSize: 0, quantityUnit: 'litre', language: 'xx' });
  assertEquals(inserted[0].protein_100, null);
  assertEquals(inserted[0].salt_100, null);
  assertEquals(inserted[0].serving_size, null);
  assertEquals(inserted[0].quantity_unit, 'g');
  assertEquals(inserted[0].name, { nl: "Oma's Appeltaart" });
});

Deno.test('sharing is limited per hour', async () => {
  const { d, refuse, submissions } = deps();
  refuse();
  assertEquals((await call(d, product)).status, 429);
  assertEquals(submissions.length, 0);
});

Deno.test('the web app may ask first from its own origin', async () => {
  const { d } = deps();
  const response = await handle(new Request('http://localhost/submit-product', { method: 'OPTIONS' }), d);
  assertEquals(response.status, 204);
  assertEquals(response.headers.get('Access-Control-Allow-Origin'), '*');
});
