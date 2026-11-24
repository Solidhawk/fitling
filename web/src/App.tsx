import { useCallback, useEffect, useState } from "react";
import { AuthService, type AuthState } from "./data/auth";
import { deleteAccount } from "./data/account";
import { lookUp } from "./data/profile";
import { supabase } from "./data/supabase";
import { Home } from "./Home";
import { t } from "./i18n";
import { Alert } from "./ui/Alert";
import { NeedsConnection } from "./screens/NeedsConnection";
import { Onboarding } from "./screens/Onboarding";
import { PartnerSetup } from "./screens/PartnerSetup";
import { ResetPassword } from "./screens/ResetPassword";
import { type Lookup, type Screen, screenFor } from "./screens/route";
import { VerifyEmail } from "./screens/VerifyEmail";
import { Welcome } from "./screens/Welcome";

const auth = new AuthService(supabase, `${location.origin}${import.meta.env.BASE_URL}`);

/** Picks the screen from the session and what the server has, as RootView and RootViewModel on iOS. */
export function App() {
  const [authState, setAuthState] = useState<AuthState>(auth.state);
  const [lookup, setLookup] = useState<Lookup>({ kind: "pending" });
  const [screen, setScreen] = useState<Screen>({ kind: "loading" });
  const [resettingPassword, setResettingPassword] = useState(false);
  const [deletionFailed, setDeletionFailed] = useState(false);

  useEffect(() => auth.subscribe(setAuthState), []);
  useEffect(() => {
    const { data } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY") setResettingPassword(true);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const refresh = useCallback(async () => {
    if (authState.kind !== "signedIn") return;
    setLookup({ kind: "pending" });
    try {
      setLookup(await lookUp(supabase, authState.userID));
    } catch {
      setLookup({ kind: "failed" });
    }
  }, [authState]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    setScreen((current) => screenFor(authState, lookup, current));
  }, [authState, lookup]);

  return (
    <>
      {screen.kind === "loading" && (
        <main className="screen loading" data-screen="loading" aria-busy="true">
          <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
        </main>
      )}
      {screen.kind === "welcome" && <Welcome auth={auth} />}
      {screen.kind === "verifyEmail" && <VerifyEmail key={screen.email} auth={auth} email={screen.email} />}
      {screen.kind === "needsConnection" && <NeedsConnection onRetry={() => void refresh()} />}
      {screen.kind === "onboarding" && (
        <Onboarding
          key={screen.userID}
          userID={screen.userID}
          onFinished={() => void refresh()}
          onDeleteAccount={() => void deleteAccount(supabase, auth).catch(() => setDeletionFailed(true))}
        />
      )}
      {screen.kind === "partnerSetup" && <PartnerSetup key={screen.userID} userID={screen.userID} onFinished={() => void refresh()} />}
      {screen.kind === "home" && <Home />}
      {deletionFailed && <Alert title={t("error.server")} onClose={() => setDeletionFailed(false)} />}
      {resettingPassword && (
        <ResetPassword auth={auth} onDone={() => setResettingPassword(false)} onCancel={() => setResettingPassword(false)} />
      )}
    </>
  );
}
