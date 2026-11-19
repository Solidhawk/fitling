import { assertEquals } from '@std/assert';
import { type Deps, handle, type User } from './handler.ts';

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
