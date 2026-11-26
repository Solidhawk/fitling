import type { AuthState } from "../data/auth";

export type Screen =
  | { kind: "loading" }
  | { kind: "welcome" }
  | { kind: "verifyEmail"; email: string }
  | { kind: "needsConnection" }
  | { kind: "onboarding"; userID: string }
  | { kind: "partnerSetup"; userID: string }
  | { kind: "home"; userID: string };

/** What the server said about the signed-in user's profile and partner. */
export type Lookup = { kind: "pending" } | { kind: "failed" } | { kind: "loaded"; hasProfile: boolean; hasCreature: boolean };

/**
 * The screen to show, as RootViewModel.refresh and route do on iOS. Onboarding only starts once the server has
 * confirmed there is no profile, and checking again for the same user (a dropped connection, a tab that comes back)
 * keeps the user's answers on screen.
 */
export function screenFor(auth: AuthState, lookup: Lookup, current: Screen): Screen {
  switch (auth.kind) {
    case "loading":
      return { kind: "loading" };
    case "signedOut":
      return { kind: "welcome" };
    case "awaitingEmailVerification":
      return { kind: "verifyEmail", email: auth.email };
    case "signedIn": {
      const { userID } = auth;
      // Checking again for the same user keeps what is on screen, with the user's answers in it.
      const keeps = (current.kind === "onboarding" || current.kind === "partnerSetup" || current.kind === "home") && current.userID === userID;
      if (lookup.kind === "pending") return keeps ? current : { kind: "loading" };
      if (lookup.kind === "failed") return keeps ? current : { kind: "needsConnection" };
      if (!lookup.hasProfile) return { kind: "onboarding", userID };
      if (!lookup.hasCreature) return { kind: "partnerSetup", userID };
      return { kind: "home", userID };
    }
  }
}
