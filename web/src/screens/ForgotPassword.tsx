import { useState } from "react";
import { isPlausibleEmail, normalizedEmail } from "../credentials";
import type { AuthService } from "../data/auth";
import { t } from "../i18n";
import { PrimaryButton } from "../ui/Buttons";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";

/** Ask for a reset link (ForgotPasswordView.swift). Whether the address exists is never said. */
export function ForgotPassword({
  auth,
  initialEmail,
  onBack,
  onCreateAccount,
}: {
  auth: AuthService;
  initialEmail: string;
  onBack: () => void;
  onCreateAccount: () => void;
}) {
  const [email, setEmail] = useState(initialEmail);
  const [working, setWorking] = useState(false);
  const [messageKey, setMessageKey] = useState<string | null>(null);
  const canSubmit = !working && isPlausibleEmail(email);

  async function submit() {
    if (!canSubmit) return;
    setWorking(true);
    setMessageKey(null);
    try {
      await auth.sendPasswordReset(normalizedEmail(email));
      setMessageKey("auth.reset.sent");
    } catch (error) {
      const key = error instanceof Error ? error.message : "";
      if (key === "auth.error.rateLimited") setMessageKey("auth.reset.rateLimited");
      else if (key === "error.network") setMessageKey("error.network");
      else setMessageKey("auth.reset.sent");
    } finally {
      setWorking(false);
    }
  }

  return (
    <main className="screen">
      <NavBar title={t("auth.forgot.title")} back={t("auth.signIn.title")} onBack={onBack} />
      <form
        onSubmit={(event) => {
          event.preventDefault();
          void submit();
        }}
      >
        <List>
          <ListSection>
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
          </ListSection>
          <ListSection footer={messageKey ? <span className="message">{t(messageKey)}</span> : undefined}>
            <div className="button-row">
              <PrimaryButton type="submit" disabled={!canSubmit}>
                {t("auth.forgot.submit")}
                {working && <span className="spinner" aria-hidden="true" />}
              </PrimaryButton>
            </div>
          </ListSection>
          <ListSection>
            <ListRow onClick={onCreateAccount} chevron>
              {t("auth.forgot.createAccount")}
            </ListRow>
          </ListSection>
        </List>
      </form>
    </main>
  );
}
