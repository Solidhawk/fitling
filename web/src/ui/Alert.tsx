import { useRef } from "react";
import { t } from "../i18n";
import { useDialogFocus } from "./dialogFocus";

export interface AlertAction {
  label: string;
  onSelect: () => void;
}

/**
 * A system-style alert, as .alert on iOS: one OK button, or the given actions with Cancel (`onClose`) beside them.
 * Escape is Cancel or OK.
 */
export function Alert({ title, message, actions, onClose }: { title: string; message?: string; actions?: AlertAction[]; onClose: () => void }) {
  const alert = useRef<HTMLDivElement>(null);
  useDialogFocus(alert, onClose);
  return (
    <div className="alert-backdrop">
      <div ref={alert} className="alert" role="alertdialog" aria-modal="true" aria-label={title} tabIndex={-1}>
        <p className="alert-title">{title}</p>
        {message && <p className="alert-message">{message}</p>}
        {actions ? (
          <div className="alert-buttons">
            <button type="button" className="alert-button" onClick={onClose}>
              {t("common.cancel")}
            </button>
            {actions.map((action) => (
              <button key={action.label} type="button" className="alert-button alert-button-action" onClick={action.onSelect}>
                {action.label}
              </button>
            ))}
          </div>
        ) : (
          <button type="button" className="alert-button" onClick={onClose}>
            {t("common.ok")}
          </button>
        )}
      </div>
    </div>
  );
}
