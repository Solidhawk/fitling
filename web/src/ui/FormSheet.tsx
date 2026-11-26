import { type ReactNode, useRef } from "react";
import { t } from "../i18n";
import { useDialogFocus } from "./dialogFocus";
import { List } from "./List";
import { NavBar } from "./NavBar";

/** A form as a sheet over the app, with Cancel and Save in its bar (a sheet with a NavigationStack on iOS). */
export function FormSheet({
  title,
  saveLabel,
  canSave = true,
  onSave,
  onCancel,
  children,
}: {
  title: string;
  saveLabel: string;
  canSave?: boolean;
  onSave: () => void;
  onCancel: () => void;
  children: ReactNode;
}) {
  const sheet = useRef<HTMLDivElement>(null);
  useDialogFocus(sheet, onCancel);
  return (
    <div ref={sheet} className="sheet" role="dialog" aria-modal="true" aria-label={title} tabIndex={-1}>
      <NavBar
        title={title}
        leading={
          <button type="button" className="nav-back nav-action" onClick={onCancel}>
            {t("common.cancel")}
          </button>
        }
        trailing={
          <button type="button" className="nav-back nav-action nav-confirm" disabled={!canSave} onClick={onSave}>
            {saveLabel}
          </button>
        }
      />
      <List>{children}</List>
    </div>
  );
}
