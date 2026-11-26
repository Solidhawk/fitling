import { assertEquals } from '@std/assert';
import { type Deps, handle, misconfigured, readConfig, type User } from './handler.ts';

type Recorder = Deps & { deleted: string[]; revoked: string[]; logs: string[] };

function deps(user: User | null, overrides: Partial<Deps> = {}): Recorder {
  const recorder: Recorder = {
    deleted: [],
    revoked: [],
    logs: [],
    getUser: (token) => Promise.resolve(token === 'valid-token' ? user : null),
    deleteUser: (id) => {
      recorder.deleted.push(id);
      return Promise.resolve();
    },
    revokeApple: (code) => {
      recorder.revoked.push(code);
      return Promise.resolve();
    },
    log: (message) => {
      recorder.logs.push(message);
    },
  };
  return Object.assign(recorder, overrides);
}

function request(body?: unknown, token: string | null = 'valid-token'): Request {
  const headers = new Headers({ 'Content-Type': 'application/json' });
  if (token !== null) headers.set('Authorization', `Bearer ${token}`);
  return new Request('http://localhost/delete-account', {
    method: 'POST',
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

const emailUser: User = { id: 'user-email', providers: ['email'] };
const appleUser: User = { id: 'user-apple', providers: ['apple'] };

Deno.test('missing authorization header is rejected', async () => {
  const d = deps(emailUser);
  const response = await handle(request({}, null), d);
  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: 'unauthorized' });
  assertEquals(d.deleted, []);
});

Deno.test('invalid token is rejected', async () => {
  const d = deps(emailUser);
  const response = await handle(request({}, 'forged'), d);
  assertEquals(response.status, 401);
  assertEquals(d.deleted, []);
});

Deno.test('email account is deleted without contacting Apple', async () => {
  const d = deps(emailUser);
  const response = await handle(request(), d);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { deleted: true });
  assertEquals(d.deleted, ['user-email']);
  assertEquals(d.revoked, []);
});

Deno.test('apple account revokes the token before deleting', async () => {
  const order: string[] = [];
  const d = deps(appleUser, {
    revokeApple: () => {
      order.push('revoke');
      return Promise.resolve();
    },
    deleteUser: () => {
      order.push('delete');
      return Promise.resolve();
    },
  });
  const response = await handle(request({ appleAuthorizationCode: 'code-123' }), d);
  assertEquals(response.status, 200);
  assertEquals(order, ['revoke', 'delete']);
});

Deno.test('apple account without a code is refused', async () => {
  const d = deps(appleUser);
  const response = await handle(request({}), d);
  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: 'apple_code_required' });
  assertEquals(d.deleted, []);
});

Deno.test('a failed Apple revoke still deletes the account and is logged', async () => {
  const d = deps(appleUser, { revokeApple: () => Promise.reject(new Error('apple down')) });
  const response = await handle(request({ appleAuthorizationCode: 'code-123' }), d);
  assertEquals(response.status, 200);
  assertEquals(d.deleted, ['user-apple']);
  assertEquals(d.logs.some((line) => line.startsWith('apple_revoke_failed')), true);
});

Deno.test('a failed delete returns 500', async () => {
  const d = deps(emailUser, { deleteUser: () => Promise.reject(new Error('db down')) });
  const response = await handle(request(), d);
  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: 'delete_failed' });
});

function env(values: Record<string, string>): (name: string) => string | undefined {
  return (name) => values[name];
}

Deno.test('the configuration is read from the url and the default secret key', () => {
  const config = readConfig(env({
    SUPABASE_URL: 'https://abcd.supabase.co',
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: 'sb_secret_test' }),
  }));
  assertEquals(config, { url: 'https://abcd.supabase.co', secretKey: 'sb_secret_test' });
});

Deno.test('a missing secret key is named instead of starting with an empty one', () => {
  assertEquals(readConfig(env({ SUPABASE_URL: 'https://abcd.supabase.co' })), { missing: ['SUPABASE_SECRET_KEYS'] });
  assertEquals(readConfig(env({ SUPABASE_URL: 'https://abcd.supabase.co', SUPABASE_SECRET_KEYS: 'no json' })), {
    missing: ['SUPABASE_SECRET_KEYS'],
  });
  assertEquals(readConfig(env({ SUPABASE_SECRET_KEYS: JSON.stringify({ other: 'x' }) })), {
    missing: ['SUPABASE_URL', 'SUPABASE_SECRET_KEYS'],
  });
});

Deno.test('a misconfigured function answers 500 misconfigured', async () => {
  const response = misconfigured();
  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: 'misconfigured' });
});

// The web app calls from its own origin, so the browser asks first with OPTIONS (UNFORGET S35).
Deno.test('the browser preflight is answered without a token', async () => {
  const d = deps(emailUser);
  const response = await handle(new Request('http://localhost/delete-account', { method: 'OPTIONS' }), d);
  assertEquals(response.status, 204);
  assertEquals(response.headers.get('Access-Control-Allow-Origin'), '*');
  assertEquals(response.headers.get('Access-Control-Allow-Methods'), 'POST, OPTIONS');
  assertEquals(
    response.headers.get('Access-Control-Allow-Headers'),
    'authorization, x-client-info, apikey, content-type',
  );
  assertEquals(d.deleted, []);
});

Deno.test('every answer can be read by the web app', async () => {
  for (
    const response of [
      await handle(request({}, null), deps(emailUser)),
      await handle(request(), deps(emailUser)),
      misconfigured(),
    ]
  ) {
    assertEquals(response.headers.get('Access-Control-Allow-Origin'), '*');
  }
});
