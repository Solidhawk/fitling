import { Mail } from "lucide-react";
import { useState } from "react";
import type { AuthService } from "../data/auth";
import { t } from "../i18n";
import { SecondaryButton } from "../ui/Buttons";

/** Waiting for the confirmation link (VerifyEmailView.swift). */
export function VerifyEmail({ auth, email }: { auth: AuthService; email: string }) {
  const [working, setWorking] = useState(false);
  const [messageKey, setMessageKey] = useState<string | null>(null);

  async function resend() {
    setWorking(true);
    setMessageKey(null);
    try {
      await auth.resendVerification(email);
      setMessageKey("auth.verify.resent");
    } catch (error) {
      setMessageKey(error instanceof Error ? error.message : "error.server");
    } finally {
      setWorking(false);
    }
  }

  return (
    <main className="screen padded stack-l" data-screen="verifyEmail">
      {/* The envelope as a round badge in one of the partner colours. */}
      <span className="badge" style={{ backgroundColor: "var(--pip)" }} aria-hidden="true">
        <Mail size={30} strokeWidth={2.2} />
      </span>
      <h1 className="large-title flush">{t("auth.verify.title")}</h1>
      <p>{t("auth.verify.body %@", email)}</p>
      <SecondaryButton onClick={() => void resend()} disabled={working}>
        {t("auth.verify.resend")}
      </SecondaryButton>
      <button type="button" className="text-button" onClick={() => auth.leaveVerification()}>
        {t("auth.verify.otherAddress")}
      </button>
      {messageKey && <p className="message footnote">{t(messageKey)}</p>}
    </main>
  );
}
