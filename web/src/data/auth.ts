import { AuthApiError, AuthRetryableFetchError, AuthWeakPasswordError, type SupabaseClient } from "@supabase/supabase-js";

export type AuthState =
  | { kind: "loading" }
  | { kind: "signedOut" }
  | { kind: "awaitingEmailVerification"; email: string }
  | { kind: "signedIn"; userID: string; email: string };

/**
 * The String Catalog key for what went wrong, the same as AuthFailure.messageKey on iOS
 * (AuthViewModels.swift). Thrown as the Error's message, so a form shows `t(error.message)`.
 */
export function failureKey(error: unknown): string {
  if (error instanceof AuthWeakPasswordError) return "auth.error.weakPassword";
  if (error instanceof AuthRetryableFetchError || error instanceof TypeError) return "error.network";
  if (error instanceof AuthApiError) {
    if (error.status === 429 || error.code === "over_request_rate_limit" || error.code === "over_email_send_rate_limit") {
      return "auth.error.rateLimited";
    }
    if (error.code === "invalid_credentials") return "auth.error.invalidCredentials";
    if (error.code === "email_not_confirmed") return "auth.error.emailNotConfirmed";
    if (error.code === "weak_password") return "auth.error.weakPassword";
  }
  return "error.server";
}

/** Signing in with email and password, as AuthService.swift does for the iOS app. */
export class AuthService {
  state: AuthState = { kind: "loading" };
  private listeners = new Set<(state: AuthState) => void>();

  constructor(
    readonly client: SupabaseClient,
    /** Where the links in the mails lead back to: the web app itself. */
    readonly redirectTo: string,
  ) {
    client.auth.onAuthStateChange((_event, session) => {
      if (session?.user) {
        this.set({ kind: "signedIn", userID: session.user.id, email: session.user.email ?? "" });
      } else if (this.state.kind !== "awaitingEmailVerification") {
        this.set({ kind: "signedOut" });
      }
    });
  }

  subscribe(listener: (state: AuthState) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** A repeat of the same state (a tab that comes back, a refreshed token) is no change and is not passed on. */
  private set(state: AuthState) {
    if (JSON.stringify(state) === JSON.stringify(this.state)) return;
    this.state = state;
    for (const listener of this.listeners) listener(state);
  }

  /** Runs a Supabase call; any failure becomes an Error whose message is the String Catalog key. */
  private async run<R extends { error: unknown }>(work: () => Promise<R>): Promise<R> {
    let result: R;
    try {
      result = await work();
    } catch (error) {
      throw new Error(failureKey(error));
    }
    if (result.error) throw new Error(failureKey(result.error));
    return result;
  }

  /** With email confirmation on there is no session yet: the user waits for the link. */
  async signUp(email: string, password: string): Promise<void> {
    const { data } = await this.run(() => this.client.auth.signUp({ email, password, options: { emailRedirectTo: this.redirectTo } }));
    if (data.session?.user) {
      this.set({ kind: "signedIn", userID: data.session.user.id, email });
    } else {
      this.set({ kind: "awaitingEmailVerification", email });
    }
  }

  async signIn(email: string, password: string): Promise<void> {
    const { data } = await this.run(() => this.client.auth.signInWithPassword({ email, password }));
    if (!data.user) throw new Error("error.server");
    this.set({ kind: "signedIn", userID: data.user.id, email: data.user.email ?? email });
  }

  /** Only this browser, as AuthService.swift with scope .local: the user's other devices stay signed in. */
  async signOut(): Promise<void> {
    await this.run(() => this.client.auth.signOut({ scope: "local" }));
    this.set({ kind: "signedOut" });
  }

  async sendPasswordReset(email: string): Promise<void> {
    await this.run(() => this.client.auth.resetPasswordForEmail(email, { redirectTo: this.redirectTo }));
  }

  async updatePassword(password: string): Promise<void> {
    await this.run(() => this.client.auth.updateUser({ password }));
  }

  async resendVerification(email: string): Promise<void> {
    await this.run(() => this.client.auth.resend({ type: "signup", email, options: { emailRedirectTo: this.redirectTo } }));
  }

  /** Back to Welkom from "confirm your email", for example after a typo in the address. */
  leaveVerification(): void {
    if (this.state.kind === "awaitingEmailVerification") this.set({ kind: "signedOut" });
  }
}
