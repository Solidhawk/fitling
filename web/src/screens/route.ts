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
 * confirmed there is no profile, and a dropped connection halfway through onboarding or partner setup keeps the
 * user's answers on screen.
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
      if (lookup.kind === "pending") return { kind: "loading" };
      if (lookup.kind === "failed") {
        const keeps = (current.kind === "onboarding" || current.kind === "partnerSetup") && current.userID === userID;
        return keeps ? current : { kind: "needsConnection" };
      }
      if (!lookup.hasProfile) return { kind: "onboarding", userID };
      if (!lookup.hasCreature) return { kind: "partnerSetup", userID };
      return { kind: "home", userID };
    }
  }
}
