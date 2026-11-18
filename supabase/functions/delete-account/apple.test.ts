import { assertEquals, assertRejects } from '@std/assert';
import { type AppleConfig, makeClientSecret, revokeAppleToken } from './apple.ts';

async function testConfig(): Promise<{ config: AppleConfig; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const base64 = btoa(String.fromCharCode(...pkcs8));
  const pem = `-----BEGIN PRIVATE KEY-----\n${base64.match(/.{1,64}/g)!.join('\n')}\n-----END PRIVATE KEY-----`;
  return {
    config: { teamId: 'TEAM123456', keyId: 'KEY1234567', clientId: 'nl.fitling.Fitling', privateKeyPem: pem },
    publicKey: pair.publicKey,
  };
}

function decodeBase64Url(part: string): Uint8Array {
  const base64 = part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=');
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
}

function decodeJson(part: string): unknown {
  return JSON.parse(new TextDecoder().decode(decodeBase64Url(part)));
}

Deno.test('client secret is an ES256 JWT with the claims Apple requires', async () => {
  const { config, publicKey } = await testConfig();
  const jwt = await makeClientSecret(config, 1_800_000_000);
  const [header, payload, signature] = jwt.split('.');
  assertEquals(decodeJson(header), { alg: 'ES256', kid: 'KEY1234567' });
  assertEquals(decodeJson(payload), {
    iss: 'TEAM123456',
    iat: 1_800_000_000,
    exp: 1_800_000_300,
    aud: 'https://appleid.apple.com',
    sub: 'nl.fitling.Fitling',
  });
  const valid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    publicKey,
    decodeBase64Url(signature),
    new TextEncoder().encode(`${header}.${payload}`),
  );
  assertEquals(valid, true);
});

type Call = { url: string; form: Record<string, string> };

function fakeFetch(responses: Response[], calls: Call[]): typeof fetch {
  return (input, init) => {
    const form = Object.fromEntries(new URLSearchParams(init?.body as URLSearchParams));
    calls.push({ url: String(input), form });
    return Promise.resolve(responses.shift()!);
  };
}

Deno.test('revoke exchanges the code and revokes the refresh token', async () => {
  const { config } = await testConfig();
  const calls: Call[] = [];
  const fetchFn = fakeFetch([
    Response.json({ refresh_token: 'refresh-abc', access_token: 'access-abc' }),
    new Response(null, { status: 200 }),
  ], calls);
  await revokeAppleToken('code-123', config, fetchFn, 1_800_000_000);
  assertEquals(calls.map((call) => call.url), [
    'https://appleid.apple.com/auth/token',
    'https://appleid.apple.com/auth/revoke',
  ]);
  assertEquals(calls[0].form.grant_type, 'authorization_code');
  assertEquals(calls[0].form.code, 'code-123');
  assertEquals(calls[0].form.client_id, 'nl.fitling.Fitling');
  assertEquals(calls[1].form.token, 'refresh-abc');
  assertEquals(calls[1].form.token_type_hint, 'refresh_token');
  assertEquals(calls[1].form.client_secret.split('.').length, 3);
});

Deno.test('a failed token exchange throws', async () => {
  const { config } = await testConfig();
  const fetchFn = fakeFetch([Response.json({ error: 'invalid_grant' }, { status: 400 })], []);
  await assertRejects(() => revokeAppleToken('code-123', config, fetchFn, 1_800_000_000));
});

Deno.test('a failed revoke throws', async () => {
  const { config } = await testConfig();
  const fetchFn = fakeFetch([
    Response.json({ refresh_token: 'refresh-abc' }),
    new Response(null, { status: 500 }),
  ], []);
  await assertRejects(() => revokeAppleToken('code-123', config, fetchFn, 1_800_000_000));
});
