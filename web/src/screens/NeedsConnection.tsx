import { WifiOff } from "lucide-react";
import { t } from "../i18n";
import { SecondaryButton } from "../ui/Buttons";

/** Signed in, but the server could not be asked yet whether there is a profile (NeedsConnectionView). */
export function NeedsConnection({ onRetry }: { onRetry: () => void }) {
  return (
    <main className="screen padded unavailable" data-screen="needsConnection">
      <WifiOff aria-hidden="true" size={44} />
      <h1 className="title">{t("common.connection.title")}</h1>
      <p className="secondary">{t("common.connection.body")}</p>
      <SecondaryButton onClick={onRetry}>{t("common.connection.retry")}</SecondaryButton>
    </main>
  );
}
