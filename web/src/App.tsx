import { useCallback, useEffect, useRef, useState } from "react";
import { AuthService, type AuthState } from "./data/auth";
import { useCoreFailure } from "./core/useCore";
import { deleteAccount } from "./data/account";
import { keepPhotosFor } from "./data/photoOwner";
import { flush, noNetwork, setOfflineUser } from "./data/offline";
import { lookUp } from "./data/profile";
import { stopPushHere } from "./data/push";
import { sessionKey, storedUser, supabase } from "./data/supabase";
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

const auth = new AuthService(
  supabase,
  `${location.origin}${import.meta.env.BASE_URL}`,
  () => localStorage.removeItem(sessionKey),
  storedUser,
  noNetwork,
);

/** Picks the screen from the session and what the server has, as RootView and RootViewModel on iOS. */
export function App() {
  const [authState, setAuthState] = useState<AuthState>(auth.state);
  const [lookup, setLookup] = useState<Lookup>({ kind: "pending" });
  const [screen, setScreen] = useState<Screen>({ kind: "loading" });
  const [resettingPassword, setResettingPassword] = useState(false);
  const [deletionFailed, setDeletionFailed] = useState(false);

  useEffect(() => {
    const unsubscribe = auth.subscribe(setAuthState);
    // The first event may have come before this subscription.
    setAuthState(auth.state);
    return unsubscribe;
  }, []);
  useEffect(() => {
    const { data } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY") setResettingPassword(true);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const userID = authState.kind === "signedIn" ? authState.userID : undefined;

  // Nobody signed in, also after a session that ended by itself: no reminders with a partner's name and mood come to
  // this browser any more, as RootViewModel empties them on iOS.
  useEffect(() => {
    if (authState.kind === "signedOut") void stopPushHere().catch(() => undefined);
  }, [authState.kind]);

  // Progress photos and what is kept for without a connection live in this browser alone and belong to the user who
  // made them (RootViewModel.eraseLocalData). What waits is sent at sign-in, when the connection comes back and when
  // the app comes to the front.
  useEffect(() => {
    setOfflineUser(userID);
    if (!userID) return;
    void keepPhotosFor(userID);
    const send = () => void flush(supabase).catch(() => undefined);
    const visible = () => document.visibilityState === "visible" && send();
    send();
    window.addEventListener("online", send);
    document.addEventListener("visibilitychange", visible);
    return () => {
      window.removeEventListener("online", send);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [userID]);
  const currentUser = useRef(userID);
  currentUser.current = userID;

  // Asked again only when another user signs in; an answer for a user who is no longer signed in is dropped.
  const refresh = useCallback(async () => {
    setLookup({ kind: "pending" });
    if (!userID) return;
    let answer: Lookup;
    try {
      answer = await lookUp(supabase, userID);
    } catch {
      answer = { kind: "failed" };
    }
    if (currentUser.current === userID) setLookup(answer);
  }, [userID]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    setScreen((current) => screenFor(authState, lookup, current));
  }, [authState, lookup]);

  // The screens after sign-in need the rules; without them there is nothing to show but "no connection".
  const needsRules = screen.kind === "onboarding" || screen.kind === "partnerSetup" || screen.kind === "home";
  const rules = useCoreFailure(needsRules);

  return (
    <>
      {screen.kind === "loading" && (
        <main className="screen loading" data-screen="loading" aria-busy="true">
          <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
        </main>
      )}
      {screen.kind === "welcome" && <Welcome auth={auth} />}
      {screen.kind === "verifyEmail" && <VerifyEmail key={screen.email} auth={auth} email={screen.email} />}
      {(screen.kind === "needsConnection" || (needsRules && rules.failed)) && (
        <NeedsConnection
          onRetry={() => {
            rules.retry();
            void refresh();
          }}
        />
      )}
      {screen.kind === "onboarding" && !rules.failed && (
        <Onboarding
          key={screen.userID}
          userID={screen.userID}
          onFinished={() => void refresh()}
          onDeleteAccount={() => deleteAccount(supabase, auth).catch(() => setDeletionFailed(true))}
        />
      )}
      {screen.kind === "partnerSetup" && !rules.failed && <PartnerSetup key={screen.userID} userID={screen.userID} onFinished={() => void refresh()} />}
      {screen.kind === "home" && !rules.failed && <Home key={screen.userID} userID={screen.userID} auth={auth} />}
      {deletionFailed && <Alert title={t("error.server")} onClose={() => setDeletionFailed(false)} />}
      {resettingPassword && (
        <ResetPassword auth={auth} onDone={() => setResettingPassword(false)} onCancel={() => setResettingPassword(false)} />
      )}
    </>
  );
}
