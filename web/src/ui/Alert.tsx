import { useRef } from "react";
import { t } from "../i18n";
import { useDialogFocus } from "./dialogFocus";

/** A system-style alert with one OK button, as .alert on iOS. */
export function Alert({ title, message, onClose }: { title: string; message?: string; onClose: () => void }) {
  const alert = useRef<HTMLDivElement>(null);
  useDialogFocus(alert, onClose);
  return (
    <div className="alert-backdrop">
      <div ref={alert} className="alert" role="alertdialog" aria-modal="true" aria-label={title} tabIndex={-1}>
        <p className="alert-title">{title}</p>
        {message && <p className="alert-message">{message}</p>}
        <button type="button" className="alert-button" onClick={onClose}>
          {t("common.ok")}
        </button>
      </div>
    </div>
  );
}
