import { useState } from "react";
import { minimumPasswordLength } from "../credentials";
import type { AuthService } from "../data/auth";
import { t } from "../i18n";
import { PrimaryButton } from "../ui/Buttons";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";

/** A new password after the reset link (ResetPasswordView.swift), as a sheet over the app. */
export function ResetPassword({ auth, onDone, onCancel }: { auth: AuthService; onDone: () => void; onCancel: () => void }) {
  const [password, setPassword] = useState("");
  const [working, setWorking] = useState(false);
  const [messageKey, setMessageKey] = useState<string | null>(null);
  const canSubmit = !working && password.length >= minimumPasswordLength;

  async function submit() {
    if (!canSubmit) return;
    setWorking(true);
    setMessageKey(null);
    try {
      await auth.updatePassword(password);
      onDone();
    } catch (error) {
      setMessageKey(error instanceof Error ? error.message : "error.server");
    } finally {
      setWorking(false);
    }
  }

  return (
    <div className="sheet" role="dialog" aria-modal="true" aria-label={t("auth.reset.title")}>
      <NavBar
        title={t("auth.reset.title")}
        trailing={
          <button type="button" className="nav-back" onClick={onCancel}>
            {t("common.cancel")}
          </button>
        }
      />
      <form
        onSubmit={(event) => {
          event.preventDefault();
          void submit();
        }}
      >
        <List>
          <ListSection footer={t("auth.password.hint")}>
            <ListRow>
              <input
                className="text-field"
                type="password"
                autoComplete="new-password"
                placeholder={t("auth.reset.field")}
                aria-label={t("auth.reset.field")}
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </ListRow>
          </ListSection>
          <ListSection footer={messageKey ? <span className="message">{t(messageKey)}</span> : undefined}>
            <div className="button-row">
              <PrimaryButton type="submit" disabled={!canSubmit}>
                {t("auth.reset.submit")}
                {working && <span className="spinner" aria-hidden="true" />}
              </PrimaryButton>
            </div>
          </ListSection>
        </List>
      </form>
    </div>
  );
}
