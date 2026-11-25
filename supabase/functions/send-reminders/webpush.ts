// Web Push for the reminders of the web version (web phase 7), with WebCrypto only: the message encrypted for the
// browser (RFC 8291, aes128gcm of RFC 8188) and the server's signature for the push service (VAPID, RFC 8292).

/** Bytes in an ordinary ArrayBuffer, as WebCrypto takes them. */
export type Bytes = Uint8Array<ArrayBuffer>;

export function base64url(bytes: Bytes): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

export function fromBase64url(text: string): Bytes {
  const plain = text.replaceAll('-', '+').replaceAll('_', '/');
  const binary = atob(plain + '='.repeat((4 - (plain.length % 4)) % 4));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function concat(...parts: Bytes[]): Bytes {
  const all = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    all.set(part, offset);
    offset += part.length;
  }
  return all;
}

async function hkdf(salt: Bytes, ikm: Bytes, info: Bytes, length: number): Promise<Bytes> {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info }, key, length * 8));
}

/** The key pair and salt of one message; fresh for every message, given only by the test of the RFC's example. */
export type Ephemeral = { privateKey: CryptoKey; publicKey: Bytes; salt: Bytes };

async function freshEphemeral(): Promise<Ephemeral> {
  const pair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, false, ['deriveBits']);
  const publicKey = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey));
  return { privateKey: pair.privateKey, publicKey, salt: crypto.getRandomValues(new Uint8Array(16)) };
}

/** One record is plenty for a reminder: the message must stay under 4 kB anyway. */
const recordSize = 4096;
const text = new TextEncoder();

/**
 * The body of a push message for a browser with public key `p256dh` and secret `auth` (both base64url, as the
 * browser's PushSubscription gives them): RFC 8291 section 3.4, one record with the delimiter 0x02 and no padding.
 */
export async function encrypt(
  message: Bytes,
  p256dh: string,
  auth: string,
  ephemeral?: Ephemeral,
): Promise<Bytes> {
  const uaPublic = fromBase64url(p256dh);
  const { privateKey, publicKey: asPublic, salt } = ephemeral ?? await freshEphemeral();
  const uaKey = await crypto.subtle.importKey('raw', uaPublic, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const ecdhSecret = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, privateKey, 256));
  const keyInfo = concat(text.encode('WebPush: info\0'), uaPublic, asPublic);
  const ikm = await hkdf(fromBase64url(auth), ecdhSecret, keyInfo, 32);
  const cek = await hkdf(salt, ikm, text.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, text.encode('Content-Encoding: nonce\0'), 12);
  const key = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  const record = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, key, concat(message, new Uint8Array([2]))),
  );
  if (record.length > recordSize) throw new Error('message too long for one record');
  const size = new Uint8Array(4);
  new DataView(size.buffer).setUint32(0, recordSize);
  return concat(salt, size, new Uint8Array([asPublic.length]), asPublic, record);
}

/** The server's own key pair for VAPID, base64url: the uncompressed public point and the private value. */
export type VapidKeys = { publicKey: string; privateKey: string };

/** How long the signature holds: within the 24 hours of RFC 8292, and well within any push service's limit. */
const tokenSeconds = 3600;

/**
 * The Authorization header for one push service: a JWT signed with ES256 for the service's origin, and the public key
 * the browser was subscribed with (RFC 8292 section 3). `subject` is how the push service can reach the sender.
 */
export async function vapidAuthorization(
  endpoint: string,
  keys: VapidKeys,
  subject: string,
  now: Date,
): Promise<string> {
  const point = fromBase64url(keys.publicKey);
  const signer = await crypto.subtle.importKey(
    'jwk',
    {
      kty: 'EC',
      crv: 'P-256',
      d: keys.privateKey,
      x: base64url(point.slice(1, 33)),
      y: base64url(point.slice(33, 65)),
    },
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  const json = (value: unknown) => base64url(text.encode(JSON.stringify(value)));
  const claims = {
    aud: new URL(endpoint).origin,
    exp: Math.floor(now.getTime() / 1000) + tokenSeconds,
    sub: subject,
  };
  const unsigned = `${json({ typ: 'JWT', alg: 'ES256' })}.${json(claims)}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, signer, text.encode(unsigned)),
  );
  return `vapid t=${unsigned}.${base64url(signature)}, k=${keys.publicKey}`;
}

/** A new VAPID key pair (vapid-keys.ts): made once, on the owner's own computer. */
export async function newVapidKeys(): Promise<VapidKeys> {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const publicKey = base64url(new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey)));
  const { d } = await crypto.subtle.exportKey('jwk', pair.privateKey);
  if (!d) throw new Error('no private value');
  return { publicKey, privateKey: d };
}
