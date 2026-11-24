import { useEffect, useRef } from "react";
import { t } from "../i18n";

/** A system-style alert with one OK button, as .alert on iOS. */
export function Alert({ title, message, onClose }: { title: string; message?: string; onClose: () => void }) {
  const button = useRef<HTMLButtonElement>(null);
  useEffect(() => button.current?.focus(), []);
  return (
    <div className="alert-backdrop">
      <div className="alert" role="alertdialog" aria-modal="true" aria-label={title}>
        <p className="alert-title">{title}</p>
        {message && <p className="alert-message">{message}</p>}
        <button ref={button} type="button" className="alert-button" onClick={onClose}>
          {t("common.ok")}
        </button>
      </div>
    </div>
  );
}
