import type { SupabaseClient } from "@supabase/supabase-js";

export type AuthState =
  | { kind: "loading" }
  | { kind: "signedOut" }
  | { kind: "awaitingEmailVerification"; email: string }
  | { kind: "signedIn"; userID: string; email: string };

export class AuthService {
  state: AuthState = { kind: "loading" };

  constructor(
    readonly client: SupabaseClient,
    readonly redirectTo: string,
  ) {}

  async signUp(_email: string, _password: string): Promise<void> {
    throw new Error("not written yet");
  }

  async signIn(_email: string, _password: string): Promise<void> {
    throw new Error("not written yet");
  }

  async signOut(): Promise<void> {
    throw new Error("not written yet");
  }
}
