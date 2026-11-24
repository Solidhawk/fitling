import { useState } from "react";
import type { AuthService } from "../data/auth";
import { t } from "../i18n";
import { species } from "../partner/species";
import { SecondaryButton } from "../ui/Buttons";
import { FigureTile } from "../ui/FigureTile";
import { EmailAuth } from "./EmailAuth";
import { ForgotPassword } from "./ForgotPassword";

type Page = { kind: "welcome" } | { kind: "email"; mode: "signIn" | "signUp" } | { kind: "forgot"; email: string };

/**
 * The catalog of the sixteen partners with the sign-in actions within thumb reach (WelcomeView.swift). On the web
 * only email: Sign in with Apple needs the developer account, Google is not set up yet (D-24).
 */
export function Welcome({ auth }: { auth: AuthService }) {
  const [stack, setStack] = useState<Page[]>([{ kind: "welcome" }]);
  const page = stack[stack.length - 1];
  const push = (next: Page) => setStack([...stack, next]);
  const pop = () => setStack(stack.slice(0, -1));

  if (page.kind === "email") {
    return (
      <EmailAuth key={page.mode} auth={auth} initialMode={page.mode} onBack={pop} onForgot={(email) => push({ kind: "forgot", email })} />
    );
  }
  if (page.kind === "forgot") {
    return (
      <ForgotPassword
        auth={auth}
        initialEmail={page.email}
        onBack={pop}
        onCreateAccount={() => push({ kind: "email", mode: "signUp" })}
      />
    );
  }
  return (
    <main className="screen welcome" data-screen="welcome">
      <div className="padded stack-xl">
        <div className="stack-s">
          <h1 className="large-title flush">{t("welcome.title")}</h1>
          <p className="title3">{t("welcome.tagline")}</p>
        </div>
        <div className="catalog">
          {species.map((name) => (
            <FigureTile key={name} species={name} />
          ))}
        </div>
      </div>
      <div className="welcome-actions">
        <SecondaryButton onClick={() => push({ kind: "email", mode: "signIn" })} data-testid="welcome.email">
          {t("welcome.email")}
        </SecondaryButton>
      </div>
    </main>
  );
}
