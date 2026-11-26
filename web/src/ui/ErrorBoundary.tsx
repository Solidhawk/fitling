import { Component, type ReactNode } from "react";
import { t } from "../i18n";
import { SecondaryButton } from "./Buttons";

/**
 * When a screen fails while drawing, the error of the app with a way to start again, instead of an empty page.
 * Starting again reloads the app; what is on the server stays.
 */
export class ErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  render() {
    if (!this.state.failed) return this.props.children;
    return (
      <main className="screen padded unavailable" data-screen="failed">
        <p>{t("error.server")}</p>
        <SecondaryButton onClick={() => location.reload()}>{t("common.connection.retry")}</SecondaryButton>
      </main>
    );
  }
}
