import type { SupabaseClient } from "@supabase/supabase-js";
import { expect, test } from "vitest";
import { AuthService, type AuthState } from "./auth";

/** Just enough of the Supabase client to drive the auth state, without a server. */
function fake() {
  const listeners: ((event: string, session: unknown) => void)[] = [];
  const signOuts: unknown[] = [];
  const client = {
    auth: {
      onAuthStateChange(listener: (event: string, session: unknown) => void) {
        listeners.push(listener);
        return { data: { subscription: { unsubscribe() {} } } };
      },
      async signOut(options?: unknown) {
        signOuts.push(options);
        return { error: null };
      },
    },
  } as unknown as SupabaseClient;
  const emit = (event: string, session: unknown) => listeners.forEach((listener) => listener(event, session));
  return { auth: new AuthService(client, "http://localhost/"), emit, signOuts };
}

const session = { user: { id: "u1", email: "a@b.nl" } };

// AuthService.swift signs out with scope .local: the user's iPhone stays signed in.
test("signing out here leaves the user's other devices signed in", async () => {
  const { auth, signOuts } = fake();
  await auth.signOut();
  expect(signOuts).toEqual([{ scope: "local" }]);
  expect(auth.state).toEqual({ kind: "signedOut" });
});

// A tab that comes back, a refreshed token or another tab repeat the session; the screen must not start over.
test("the same session again is not a change", () => {
  const { auth, emit } = fake();
  const seen: AuthState[] = [];
  auth.subscribe((state) => seen.push(state));
  emit("INITIAL_SESSION", session);
  emit("SIGNED_IN", session);
  emit("TOKEN_REFRESHED", session);
  expect(seen).toEqual([{ kind: "signedIn", userID: "u1", email: "a@b.nl" }]);
  emit("SIGNED_OUT", null);
  expect(seen.at(-1)).toEqual({ kind: "signedOut" });
});
