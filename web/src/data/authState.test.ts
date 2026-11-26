import { AuthRetryableFetchError, type SupabaseClient } from "@supabase/supabase-js";
import { expect, test } from "vitest";
import { AuthService, type AuthState } from "./auth";

/** Just enough of the Supabase client to drive the auth state, without a server. */
function fake(offline = false) {
  const listeners: ((event: string, session: unknown) => void)[] = [];
  const signOuts: unknown[] = [];
  let forgotten = false;
  let refreshing = true;
  const client = {
    auth: {
      onAuthStateChange(listener: (event: string, session: unknown) => void) {
        listeners.push(listener);
        return { data: { subscription: { unsubscribe() {} } } };
      },
      async signOut(options?: unknown) {
        signOuts.push(options);
        return { error: offline ? new AuthRetryableFetchError("Failed to fetch", 0) : null };
      },
      async stopAutoRefresh() {
        refreshing = false;
      },
    },
  } as unknown as SupabaseClient;
  const emit = (event: string, session: unknown) => listeners.forEach((listener) => listener(event, session));
  const auth = new AuthService(client, "http://localhost/", () => {
    forgotten = true;
  });
  return { auth, emit, signOuts, forgotten: () => forgotten, refreshing: () => refreshing };
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

// AuthService.swift: without a connection signing out still signs out here; the session on this device is forgotten.
test("signing out without a connection still signs out", async () => {
  const { auth, emit, forgotten, refreshing } = fake(true);
  emit("INITIAL_SESSION", session);
  await auth.signOut();
  expect(auth.state).toEqual({ kind: "signedOut" });
  expect(forgotten()).toBe(true);
  expect(refreshing()).toBe(false);
});
