import { assertEquals, assertMatch } from '@std/assert';
import { base64url, type Bytes, encrypt, fromBase64url, newVapidKeys, vapidAuthorization } from './webpush.ts';

// RFC 8291, section 5 and appendix A: the example message, with the keys and salt it uses.
const vector = {
  plaintext: 'V2hlbiBJIGdyb3cgdXAsIEkgd2FudCB0byBiZSBhIHdhdGVybWVsb24',
  asPrivate: 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw',
  asPublic: 'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8',
  uaPrivate: 'q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94',
  uaPublic: 'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4',
  authSecret: 'BTBZMqHH6r4Tts7J_aSIgg',
  salt: 'DGv6ra1nlYgDCS1FRnbzlw',
  body: 'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml' +
    'mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT' +
    'pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN',
};

/** An ECDH private key from the raw private value and its public point, as WebCrypto takes it. */
function ecdhKey(privateKey: string, publicKey: string): Promise<CryptoKey> {
  const point = fromBase64url(publicKey);
  return crypto.subtle.importKey(
    'jwk',
    {
      kty: 'EC',
      crv: 'P-256',
      d: privateKey,
      x: base64url(point.slice(1, 33)),
      y: base64url(point.slice(33, 65)),
    },
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    ['deriveBits'],
  );
}

async function hkdf(salt: Bytes, ikm: Bytes, info: Bytes, length: number): Promise<Bytes> {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info }, key, length * 8));
}

/** The browser's side of RFC 8291, written out here so the test does not lean on the code it checks. */
async function decrypt(body: Bytes, uaPrivate: string, uaPublic: string, authSecret: string): Promise<string> {
  const salt = body.slice(0, 16);
  const idLength = body[20];
  const asPublic = body.slice(21, 21 + idLength);
  const ciphertext = body.slice(21 + idLength);
  const asKey = await crypto.subtle.importKey('raw', asPublic, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const secret = new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'ECDH', public: asKey }, await ecdhKey(uaPrivate, uaPublic), 256),
  );
  const text = new TextEncoder();
  const keyInfo = new Uint8Array([...text.encode('WebPush: info\0'), ...fromBase64url(uaPublic), ...asPublic]);
  const ikm = await hkdf(fromBase64url(authSecret), secret, keyInfo, 32);
  const cek = await hkdf(salt, ikm, text.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, text.encode('Content-Encoding: nonce\0'), 12);
  const key = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['decrypt']);
  const padded = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, key, ciphertext));
  // The last record ends with the delimiter 0x02, then only zeros.
  const end = padded.lastIndexOf(2);
  assertEquals([...padded.slice(end + 1)].every((byte) => byte === 0), true);
  return new TextDecoder().decode(padded.slice(0, end));
}

Deno.test('the example message of RFC 8291 comes out bit for bit', async () => {
  const body = await encrypt(fromBase64url(vector.plaintext), vector.uaPublic, vector.authSecret, {
    privateKey: await ecdhKey(vector.asPrivate, vector.asPublic),
    publicKey: fromBase64url(vector.asPublic),
    salt: fromBase64url(vector.salt),
  });
  assertEquals(base64url(body), vector.body);
});

Deno.test('the browser can read what is sent, with fresh keys every time', async () => {
  const message = JSON.stringify({ title: 'Pip', body: 'Nog niets gegeten vandaag? Ik heb trek.' });
  const first = await encrypt(new TextEncoder().encode(message), vector.uaPublic, vector.authSecret);
  const second = await encrypt(new TextEncoder().encode(message), vector.uaPublic, vector.authSecret);
  assertEquals(await decrypt(first, vector.uaPrivate, vector.uaPublic, vector.authSecret), message);
  assertEquals(await decrypt(second, vector.uaPrivate, vector.uaPublic, vector.authSecret), message);
  // A new salt and a new key of the server for each message (RFC 8291, section 3.1).
  assertEquals(base64url(first.slice(0, 16)) === base64url(second.slice(0, 16)), false);
  assertEquals(base64url(first.slice(21, 86)) === base64url(second.slice(21, 86)), false);
});

Deno.test('the VAPID header carries a token the push service can check (RFC 8292)', async () => {
  const keys = { publicKey: vector.asPublic, privateKey: vector.asPrivate };
  const now = new Date('2026-11-25T12:00:00Z');
  const header = await vapidAuthorization(
    'https://web.push.apple.com/QGuQyavXutnMnZw',
    keys,
    'https://example.test/',
    now,
  );
  assertMatch(header, /^vapid t=[\w-]+\.[\w-]+\.[\w-]+, k=[\w-]+$/);
  const [, token, k] = /^vapid t=(.+), k=(.+)$/.exec(header)!;
  assertEquals(k, vector.asPublic);
  const [head, claims, signature] = token.split('.');
  assertEquals(JSON.parse(new TextDecoder().decode(fromBase64url(head))), { typ: 'JWT', alg: 'ES256' });
  assertEquals(JSON.parse(new TextDecoder().decode(fromBase64url(claims))), {
    aud: 'https://web.push.apple.com',
    exp: now.getTime() / 1000 + 3600,
    sub: 'https://example.test/',
  });
  const verifier = await crypto.subtle.importKey(
    'raw',
    fromBase64url(vector.asPublic),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['verify'],
  );
  const signed = new TextEncoder().encode(`${head}.${claims}`);
  const valid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    verifier,
    fromBase64url(signature),
    signed,
  );
  assertEquals(valid, true);
});

Deno.test('a new VAPID key pair signs what its public key checks', async () => {
  const keys = await newVapidKeys();
  assertEquals(fromBase64url(keys.publicKey).length, 65);
  assertEquals(fromBase64url(keys.privateKey).length, 32);
  const header = await vapidAuthorization(
    'https://fcm.googleapis.com/fcm/send/x',
    keys,
    'https://example.test/',
    new Date(),
  );
  const [, token] = /^vapid t=(.+), k=/.exec(header)!;
  const [head, claims, signature] = token.split('.');
  const verifier = await crypto.subtle.importKey(
    'raw',
    fromBase64url(keys.publicKey),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['verify'],
  );
  const signed = new TextEncoder().encode(`${head}.${claims}`);
  assertEquals(
    await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, verifier, fromBase64url(signature), signed),
    true,
  );
});
