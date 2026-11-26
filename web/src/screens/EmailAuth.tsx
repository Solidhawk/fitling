import { useState } from "react";
import { isPlausibleEmail, minimumPasswordLength, normalizedEmail } from "../credentials";
import type { AuthService } from "../data/auth";
import { t } from "../i18n";
import { PrimaryButton } from "../ui/Buttons";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";

/** Sign in or create an account with email and password (EmailAuthView.swift). */
export function EmailAuth({
  auth,
  initialMode,
  onBack,
  onForgot,
}: {
  auth: AuthService;
  initialMode: "signIn" | "signUp";
  onBack: () => void;
  onForgot: (email: string) => void;
}) {
  const [mode, setMode] = useState(initialMode);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [working, setWorking] = useState(false);
  const [messageKey, setMessageKey] = useState<string | null>(null);
  const isSignUp = mode === "signUp";
  const canSubmit = !working && isPlausibleEmail(email) && password.length >= minimumPasswordLength;

  async function submit() {
    if (!canSubmit) return;
    setWorking(true);
    setMessageKey(null);
    try {
      if (isSignUp) await auth.signUp(normalizedEmail(email), password);
      else await auth.signIn(normalizedEmail(email), password);
    } catch (error) {
      setMessageKey(error instanceof Error ? error.message : "error.server");
    } finally {
      setWorking(false);
    }
  }

  return (
    <main className="screen">
      <NavBar title={t(isSignUp ? "auth.signUp.title" : "auth.signIn.title")} back={t("welcome.title")} onBack={onBack} />
      <form
        onSubmit={(event) => {
          event.preventDefault();
          void submit();
        }}
      >
        <List>
          <ListSection footer={isSignUp ? t("auth.password.hint") : undefined}>
            <ListRow>
              <input
                className="text-field"
                type="email"
                autoComplete="username"
                autoCapitalize="none"
                spellCheck={false}
                placeholder={t("auth.email.field")}
                aria-label={t("auth.email.field")}
                value={email}
                onChange={(event) => setEmail(event.target.value)}
              />
            </ListRow>
            <ListRow>
              <input
                className="text-field"
                type="password"
                autoComplete={isSignUp ? "new-password" : "current-password"}
                placeholder={t("auth.password.field")}
                aria-label={t("auth.password.field")}
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </ListRow>
          </ListSection>
          <ListSection footer={messageKey ? <span className="message">{t(messageKey)}</span> : undefined}>
            <div className="button-row">
              <PrimaryButton type="submit" disabled={!canSubmit} data-testid="auth.submit">
                {t(isSignUp ? "auth.signUp.submit" : "auth.signIn.submit")}
                {working && <span className="spinner" aria-hidden="true" />}
              </PrimaryButton>
            </div>
          </ListSection>
          <ListSection>
            <ListRow onClick={() => setMode(isSignUp ? "signIn" : "signUp")}>{t(isSignUp ? "auth.switch.toSignIn" : "auth.switch.toSignUp")}</ListRow>
            {!isSignUp && (
              <ListRow onClick={() => onForgot(email)} chevron>
                {t("auth.forgot.link")}
              </ListRow>
            )}
          </ListSection>
        </List>
      </form>
    </main>
  );
}
