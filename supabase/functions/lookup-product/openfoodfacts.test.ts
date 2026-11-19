import { assertEquals, assertRejects } from '@std/assert';
import { fetchOffProduct, SourceUnavailable } from './openfoodfacts.ts';

const fixture = await Deno.readTextFile(new URL('./fixtures/off-8712100849084.json', import.meta.url));

function deps(responses: (() => Response)[]) {
  const calls: { url: string; userAgent: string | null }[] = [];
  const waits: number[] = [];
  return {
    calls,
    waits,
    fetch: (input: string | URL | Request, init?: RequestInit) => {
      calls.push({ url: String(input), userAgent: new Headers(init?.headers).get('User-Agent') });
      const next = responses.shift();
      if (!next) throw new Error('no more responses');
      return Promise.resolve(next());
    },
    sleep: (ms: number) => {
      waits.push(ms);
      return Promise.resolve();
    },
    userAgent: 'Fitling/1.0 (test)',
  };
}

Deno.test('asks Open Food Facts for the product with our user agent', async () => {
  const d = deps([() => new Response(fixture, { status: 200 })]);
  const product = await fetchOffProduct('8712100849084', d) as { code: string };
  assertEquals(product.code, '8712100849084');
  assertEquals(d.calls.length, 1);
  assertEquals(d.calls[0].url.startsWith('https://world.openfoodfacts.org/api/v2/product/8712100849084?fields='), true);
  assertEquals(d.calls[0].userAgent, 'Fitling/1.0 (test)');
});

Deno.test('an unknown product is null, not an error', async () => {
  const body = JSON.stringify({ code: '4006381333931', status: 0, status_verbose: 'product not found' });
  const d = deps([() => new Response(body, { status: 404 })]);
  assertEquals(await fetchOffProduct('4006381333931', d), null);
});

Deno.test('retries three times on a 503, waiting 1, 2 and 4 seconds', async () => {
  const unavailable = () => new Response('busy', { status: 503 });
  const d = deps([unavailable, unavailable, unavailable, () => new Response(fixture, { status: 200 })]);
  const product = await fetchOffProduct('8712100849084', d);
  assertEquals(product !== null, true);
  assertEquals(d.calls.length, 4);
  assertEquals(d.waits, [1000, 2000, 4000]);
});

Deno.test('gives up after the third retry', async () => {
  const unavailable = () => new Response('busy', { status: 503 });
  const d = deps([unavailable, unavailable, unavailable, unavailable]);
  await assertRejects(() => fetchOffProduct('8712100849084', d), SourceUnavailable);
  assertEquals(d.calls.length, 4);
});

Deno.test('a network error counts as unavailable', async () => {
  const failing = () => {
    throw new TypeError('connection reset');
  };
  const d = deps([failing, failing, failing, failing]);
  await assertRejects(() => fetchOffProduct('8712100849084', d), SourceUnavailable);
});
