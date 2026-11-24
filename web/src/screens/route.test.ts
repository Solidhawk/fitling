import { expect, test } from "vitest";
import { screenFor } from "./route";

const signedIn = { kind: "signedIn", userID: "u1", email: "a@b.nl" } as const;

test("before the session is known: loading", () => {
  expect(screenFor({ kind: "loading" }, { kind: "pending" }, { kind: "loading" })).toEqual({ kind: "loading" });
});

test("signed out: welcome; waiting for the link: verify email", () => {
  expect(screenFor({ kind: "signedOut" }, { kind: "pending" }, { kind: "loading" })).toEqual({ kind: "welcome" });
  expect(screenFor({ kind: "awaitingEmailVerification", email: "a@b.nl" }, { kind: "pending" }, { kind: "welcome" })).toEqual({
    kind: "verifyEmail",
    email: "a@b.nl",
  });
});

test("signed in: onboarding, partner setup or home, by what the server has", () => {
  const welcome = { kind: "welcome" } as const;
  expect(screenFor(signedIn, { kind: "pending" }, welcome)).toEqual({ kind: "loading" });
  expect(screenFor(signedIn, { kind: "loaded", hasProfile: false, hasCreature: false }, welcome)).toEqual({ kind: "onboarding", userID: "u1" });
  expect(screenFor(signedIn, { kind: "loaded", hasProfile: true, hasCreature: false }, welcome)).toEqual({ kind: "partnerSetup", userID: "u1" });
  expect(screenFor(signedIn, { kind: "loaded", hasProfile: true, hasCreature: true }, welcome)).toEqual({ kind: "home", userID: "u1" });
});

// As RootViewModel.route: never start onboarding before the server confirmed there is no profile, and keep
// the user's answers when the connection drops halfway.
test("without a connection: needs connection, but onboarding and partner setup keep going", () => {
  const failed = { kind: "failed" } as const;
  expect(screenFor(signedIn, failed, { kind: "welcome" })).toEqual({ kind: "needsConnection" });
  expect(screenFor(signedIn, failed, { kind: "onboarding", userID: "u1" })).toEqual({ kind: "onboarding", userID: "u1" });
  expect(screenFor(signedIn, failed, { kind: "partnerSetup", userID: "u1" })).toEqual({ kind: "partnerSetup", userID: "u1" });
});
