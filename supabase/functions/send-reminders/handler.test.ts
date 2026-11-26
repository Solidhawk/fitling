import { assertEquals } from '@std/assert';
import { type Deps, type Due, handle } from './handler.ts';

const now = new Date('2026-11-25T11:30:00Z');
const secret = 'sb_secret_test';
// The key pair of RFC 8291, section 5: a valid P-256 pair, used here as the VAPID keys.
const vapid = {
  publicKey: 'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8',
  privateKey: 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw',
  subject: 'https://example.test/',
};
const browser = {
  p256dh: 'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4',
  auth: 'BTBZMqHH6r4Tts7J_aSIgg',
};

function due(id: string, overrides: Partial<Due> = {}): Due {
  return {
    id,
    subscriptionID: `sub-${id}`,
    fireAt: '2026-11-25T11:30:00Z',
    title: 'Pip',
    body: 'Tijd voor lunch',
    endpoint: `https://web.push.apple.com/${id}`,
    claimedUntil: '2026-11-25T11:35:00.000123+00:00',
    ...browser,
    ...overrides,
  };
}

function deps(reminders: Due[], answer: (request: Request) => Response = () => new Response(null, { status: 201 })) {
  const sent: Request[] = [];
  const removed: string[] = [];
  const released: string[] = [];
  const claims: string[] = [];
  const asked: number[] = [];
  const gone: string[] = [];
  const log: string[] = [];
  const d: Deps = {
    claim: (limit) => {
      asked.push(limit);
      return Promise.resolve(reminders);
    },
    removeReminders: (ids) => {
      removed.push(...ids);
      return Promise.resolve();
    },
    release: (ids, claimedUntil) => {
      released.push(...ids);
      claims.push(claimedUntil);
      return Promise.resolve();
    },
    removeSubscription: (id) => {
      gone.push(id);
      return Promise.resolve();
    },
    send: (request) => {
      sent.push(request);
      return Promise.resolve(answer(request));
    },
    now: () => now,
    log: (message) => log.push(message),
  };
  return { d, sent, removed, released, claims, asked, gone, log };
}

function call(d: Deps, key = secret): Promise<Response> {
  return handle(
    new Request('http://localhost/send-reminders', { method: 'POST', headers: { Authorization: `Bearer ${key}` } }),
    secret,
    vapid,
    d,
  );
}

Deno.test('only the scheduler with the secret key may send', async () => {
  const { d, sent } = deps([due('a')]);
  assertEquals((await call(d, 'sb_publishable_wrong')).status, 401);
  assertEquals(sent.length, 0);
});

// Claimed first: a call still busy with a slow push service and the call of the next minute never both send it.
Deno.test('what is due is claimed first, at most 200 per call', async () => {
  const { d, asked, released } = deps([due('a')]);
  await call(d);
  assertEquals(asked, [200]);
  assertEquals(released, []);
});

Deno.test('a reminder that is due goes to its push service, encrypted, and is then done', async () => {
  const { d, sent, removed } = deps([due('a')]);
  const response = await call(d);
  assertEquals(await response.json(), { sent: 1, dropped: 0, waiting: 0 });
  assertEquals(sent[0].url, 'https://web.push.apple.com/a');
  assertEquals(sent[0].method, 'POST');
  assertEquals(sent[0].headers.get('Content-Encoding'), 'aes128gcm');
  assertEquals(sent[0].headers.get('TTL'), '1800');
  // An endpoint is whatever a browser sent: a redirect is not followed to another host.
  assertEquals(sent[0].redirect, 'manual');
  assertEquals(sent[0].headers.get('Authorization')?.startsWith('vapid t='), true);
  // 86 octets of header, then the record: the message, its delimiter and the 16-octet tag.
  assertEquals((await sent[0].arrayBuffer()).byteLength > 86 + 16, true);
  assertEquals(removed, ['a']);
});

Deno.test('a browser that unsubscribed loses its subscription', async () => {
  const { d, removed, gone } = deps(
    [due('a'), due('b')],
    (request) => new Response(null, { status: request.url.endsWith('/a') ? 410 : 404 }),
  );
  assertEquals(await (await call(d)).json(), { sent: 0, dropped: 2, waiting: 0 });
  assertEquals(gone, ['sub-a', 'sub-b']);
  assertEquals(removed, []);
});

Deno.test('a push service that is busy gets the reminder again next minute', async () => {
  const { d, removed, released } = deps(
    [due('a'), due('b')],
    (request) => new Response(null, { status: request.url.endsWith('/a') ? 429 : 503 }),
  );
  assertEquals(await (await call(d)).json(), { sent: 0, dropped: 0, waiting: 2 });
  assertEquals(removed, []);
  assertEquals(released, ['a', 'b']);
});

// Only this call's claim: a slower call that released late must not free what the next call claimed since.
Deno.test("what is released is this call's own claim", async () => {
  const { d, claims } = deps([due('a')], () => new Response(null, { status: 503 }));
  await call(d);
  assertEquals(claims, ['2026-11-25T11:35:00.000123+00:00']);
});

// Fifteen seconds per push service that does not answer, two hundred per call: the call stops well before its
// five-minute claim runs out, so the next minute's call never sends the same reminder a second time.
Deno.test('a call stops before its claim runs out and lets the rest go', async () => {
  const reminders = Array.from({ length: 20 }, (_, index) => due(`r${index}`));
  const { d, sent, released } = deps(reminders);
  let clock = now.getTime();
  d.now = () => new Date(clock);
  const answer = d.send;
  d.send = (request) => {
    clock += 100_000;
    return answer(request);
  };
  assertEquals(await (await call(d)).json(), { sent: 3, dropped: 0, waiting: 17 });
  assertEquals(sent.length, 3);
  assertEquals(released, reminders.slice(3).map((reminder) => reminder.id));
});

// Sent, but the row could not be removed: sending it again next minute would be a second message.
Deno.test('a reminder that was sent is not released when removing it fails once', async () => {
  const { d, removed, released } = deps([due('a')]);
  const remove = d.removeReminders;
  let failures = 1;
  d.removeReminders = (ids) => failures-- > 0 ? Promise.reject(new Error('timeout')) : remove(ids);
  assertEquals(await (await call(d)).json(), { sent: 1, dropped: 0, waiting: 0 });
  assertEquals(removed, ['a']);
  assertEquals(released, []);
});

Deno.test('a push service that cannot be reached gets the reminder again next minute', async () => {
  const { d, released, log } = deps([due('a')]);
  d.send = () => Promise.reject(new TypeError('connection refused'));
  assertEquals(await (await call(d)).json(), { sent: 0, dropped: 0, waiting: 1 });
  assertEquals(released, ['a']);
  assertEquals(log.length, 1);
});

Deno.test('a reminder that comes too late is not sent: never a lunch message at night', async () => {
  const { d, sent, removed } = deps([due('late', { fireAt: '2026-11-25T10:59:00Z' }), due('ok')]);
  assertEquals(await (await call(d)).json(), { sent: 1, dropped: 1, waiting: 0 });
  assertEquals(sent.map((request) => request.url), ['https://web.push.apple.com/ok']);
  assertEquals(removed.sort(), ['late', 'ok']);
});

Deno.test('a late reminder lives at the push service only until it would be too late', async () => {
  // 20 minutes late: a phone that is off gets it within the 30 minutes, never later (so never in the quiet hours).
  const { d, sent } = deps([due('a', { fireAt: '2026-11-25T11:10:00Z' })]);
  assertEquals(await (await call(d)).json(), { sent: 1, dropped: 0, waiting: 0 });
  assertEquals(sent[0].headers.get('TTL'), '600');
});

Deno.test('only the known push services are called', async () => {
  const { d, sent, removed, gone } = deps([
    due('internal', { endpoint: 'https://127.0.0.1/a' }),
    due('lookalike', { endpoint: 'https://web.push.apple.com.example.test/a' }),
    due('google', { endpoint: 'https://fcm.googleapis.com/fcm/send/a' }),
    due('mozilla', { endpoint: 'https://updates.push.services.mozilla.com/wpush/v2/a' }),
    due('windows', { endpoint: 'https://wns2-db5p.notify.windows.com/w/?token=a' }),
  ]);
  assertEquals(await (await call(d)).json(), { sent: 3, dropped: 2, waiting: 0 });
  assertEquals(sent.map((request) => new URL(request.url).host), [
    'fcm.googleapis.com',
    'updates.push.services.mozilla.com',
    'wns2-db5p.notify.windows.com',
  ]);
  assertEquals(gone, ['sub-internal', 'sub-lookalike']);
  assertEquals(removed.sort(), ['google', 'mozilla', 'windows']);
});

Deno.test('a failure for one browser does not stop the others', async () => {
  const { d, removed, log } = deps([due('a', { p256dh: 'broken' }), due('b')]);
  assertEquals(await (await call(d)).json(), { sent: 1, dropped: 1, waiting: 0 });
  assertEquals(removed.sort(), ['a', 'b']);
  assertEquals(log.length, 1);
});
