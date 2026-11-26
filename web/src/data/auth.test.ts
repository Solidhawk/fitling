import { createClient } from "@supabase/supabase-js";
import { describe, expect, test } from "vitest";
import { AuthService } from "./auth";

// Against the local Supabase that CI starts (never the real project). Without it these tests cannot run.
const url = process.env.VITE_SUPABASE_URL;
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const mailpit = "http://127.0.0.1:54324";

function service() {
  const memory = new Map<string, string>();
  const client = createClient(url ?? "", key ?? "", {
    auth: {
      storage: {
        getItem: (name) => memory.get(name) ?? null,
        setItem: (name, value) => void memory.set(name, value),
        removeItem: (name) => void memory.delete(name),
      },
      detectSessionInUrl: false,
    },
  });
  return new AuthService(client, "http://localhost:4173/fitling/");
}

/** Opens the confirmation link of the newest mail to `email`, as clicking it would. */
async function confirm(email: string) {
  let message: { ID: string } | undefined;
  for (let attempt = 0; attempt < 20 && !message; attempt++) {
    const search = await fetch(`${mailpit}/api/v1/search?query=${encodeURIComponent(`to:${email}`)}`).then((r) => r.json());
    message = search.messages?.[0];
    if (!message) await new Promise((resolve) => setTimeout(resolve, 500));
  }
  if (!message) throw new Error(`no mail for ${email}`);
  const body = await fetch(`${mailpit}/api/v1/message/${message.ID}`).then((r) => r.json());
  const link = /https?:\/\/[^\s"<>]+\/auth\/v1\/verify\?[^\s"<>]+/.exec(String(body.Text ?? body.HTML))?.[0];
  if (!link) throw new Error("no confirmation link in the mail");
  await fetch(link.replace(/&amp;/g, "&"), { redirect: "manual" });
}

const address = () => `test-${crypto.randomUUID()}@fitling.test`;

describe.runIf(url && key)("signing in with email against the local Supabase", () => {
  test("signUpNeedsTheEmailLink", async () => {
    const auth = service();
    const email = address();
    await auth.signUp(email, "lang-genoeg-wachtwoord-1");
    expect(auth.state).toEqual({ kind: "awaitingEmailVerification", email });
    await expect(auth.signIn(email, "lang-genoeg-wachtwoord-1")).rejects.toThrow("auth.error.emailNotConfirmed");
    await confirm(email);
    await auth.signIn(email, "lang-genoeg-wachtwoord-1");
    expect(auth.state).toMatchObject({ kind: "signedIn", email });
  });

  test("signInWithWrongPasswordShowsTheAppsError", async () => {
    const auth = service();
    await expect(auth.signIn(address(), "niet-het-wachtwoord")).rejects.toThrow("auth.error.invalidCredentials");
    expect(auth.state).toEqual({ kind: "signedOut" });
  });

  test("signOutReturnsToSignedOut", async () => {
    const auth = service();
    const email = address();
    await auth.signUp(email, "lang-genoeg-wachtwoord-1");
    await confirm(email);
    await auth.signIn(email, "lang-genoeg-wachtwoord-1");
    await auth.signOut();
    expect(auth.state).toEqual({ kind: "signedOut" });
  });
});

test("the local Supabase is there in CI", () => {
  if (process.env.CI) expect(url && key).toBeTruthy();
});
