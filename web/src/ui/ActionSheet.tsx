import { useRef } from "react";
import { t } from "../i18n";
import { useDialogFocus } from "./dialogFocus";

export interface SheetAction {
  label: string;
  destructive?: boolean;
  onSelect: () => void;
}

/**
 * A choice from the bottom of the screen, as .confirmationDialog with a visible title on iOS: the question, its
 * actions, and the way out apart below them. `cancelLabel` is that way out, "Annuleren" unless given.
 */
export function ActionSheet({
  title,
  message,
  actions,
  cancelLabel = t("common.cancel"),
  onCancel,
}: {
  title: string;
  message?: string;
  actions: SheetAction[];
  cancelLabel?: string;
  onCancel: () => void;
}) {
  const sheet = useRef<HTMLDivElement>(null);
  useDialogFocus(sheet, onCancel, false);

  return (
    <div className="action-sheet-backdrop" onClick={(event) => event.target === event.currentTarget && onCancel()}>
      <div ref={sheet} className="action-sheet" role="alertdialog" aria-modal="true" aria-label={title} tabIndex={-1}>
        <div className="action-sheet-group">
          <p className="action-sheet-title">{title}</p>
          {message && <p className="action-sheet-message">{message}</p>}
          {actions.map((action) => (
            <button
              key={action.label}
              type="button"
              className={action.destructive ? "action-sheet-button destructive" : "action-sheet-button"}
              onClick={action.onSelect}
            >
              {action.label}
            </button>
          ))}
        </div>
        <button type="button" className="action-sheet-button action-sheet-cancel" onClick={onCancel}>
          {cancelLabel}
        </button>
      </div>
    </div>
  );
}
