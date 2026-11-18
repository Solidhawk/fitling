export type User = { id: string; providers: string[] };

export type Deps = {
  getUser(token: string): Promise<User | null>;
  deleteUser(id: string): Promise<void>;
  revokeApple(code: string): Promise<void>;
  log(message: string): void;
};

function json(status: number, body: unknown): Response {
  return Response.json(body, { status });
}

async function appleAuthorizationCode(req: Request): Promise<string | null> {
  try {
    const body = await req.json();
    const code = body?.appleAuthorizationCode;
    return typeof code === 'string' && code !== '' ? code : null;
  } catch {
    return null;
  }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const header = req.headers.get('Authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length).trim() : '';
  if (token === '') return json(401, { error: 'unauthorized' });

  const user = await deps.getUser(token);
  if (user === null) return json(401, { error: 'unauthorized' });

  if (user.providers.includes('apple')) {
    const code = await appleAuthorizationCode(req);
    if (code === null) return json(400, { error: 'apple_code_required' });
    // Apple requires the revoke attempt, but the user's request to delete their data comes first.
    try {
      await deps.revokeApple(code);
    } catch (error) {
      deps.log(`apple_revoke_failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  try {
    await deps.deleteUser(user.id);
  } catch (error) {
    deps.log(`delete_failed: ${error instanceof Error ? error.message : String(error)}`);
    return json(500, { error: 'delete_failed' });
  }
  return json(200, { deleted: true });
}
