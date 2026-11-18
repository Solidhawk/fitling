export type AppleConfig = { teamId: string; keyId: string; clientId: string; privateKeyPem: string };

const appleIdBase = 'https://appleid.apple.com';
// Apple allows up to six months; the secret is only used for the two calls that follow.
const clientSecretLifetimeSeconds = 300;

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function pkcs8FromPem(pem: string): Uint8Array<ArrayBuffer> {
  const binary = atob(pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, ''));
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

export async function makeClientSecret(config: AppleConfig, nowSeconds: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pkcs8FromPem(config.privateKeyPem),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  const header = base64UrlJson({ alg: 'ES256', kid: config.keyId });
  const payload = base64UrlJson({
    iss: config.teamId,
    iat: nowSeconds,
    exp: nowSeconds + clientSecretLifetimeSeconds,
    aud: appleIdBase,
    sub: config.clientId,
  });
  const signingInput = `${header}.${payload}`;
  // Web Crypto returns the raw r||s signature, which is the form JWS ES256 expects.
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function postForm(fetchFn: typeof fetch, path: string, form: Record<string, string>): Promise<Response> {
  return fetchFn(`${appleIdBase}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(form),
  });
}

export async function revokeAppleToken(
  code: string,
  config: AppleConfig,
  fetchFn: typeof fetch,
  nowSeconds: number,
): Promise<void> {
  const clientSecret = await makeClientSecret(config, nowSeconds);
  const tokenResponse = await postForm(fetchFn, '/auth/token', {
    client_id: config.clientId,
    client_secret: clientSecret,
    code,
    grant_type: 'authorization_code',
  });
  if (!tokenResponse.ok) throw new Error(`apple token exchange failed with ${tokenResponse.status}`);
  const { refresh_token: refreshToken } = await tokenResponse.json();
  if (typeof refreshToken !== 'string') throw new Error('apple token exchange returned no refresh_token');

  const revokeResponse = await postForm(fetchFn, '/auth/revoke', {
    client_id: config.clientId,
    client_secret: clientSecret,
    token: refreshToken,
    token_type_hint: 'refresh_token',
  });
  if (!revokeResponse.ok) throw new Error(`apple revoke failed with ${revokeResponse.status}`);
}
