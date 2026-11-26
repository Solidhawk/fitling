import { type RefObject, useEffect, useRef } from "react";

const focusable = 'button:not([disabled]), input:not([disabled]), select:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])';

/**
 * A dialog takes the focus while it is open, keeps Tab inside it, closes on Escape and gives the focus back to what
 * opened it, as VoiceOver and a keyboard expect of a sheet or alert on iOS. Without `focusFirst` the dialog itself
 * takes the focus, so Enter cannot set off a destructive first action.
 */
export function useDialogFocus(dialog: RefObject<HTMLElement | null>, onEscape: () => void, focusFirst = true) {
  const escape = useRef(onEscape);
  escape.current = onEscape;

  useEffect(() => {
    const element = dialog.current;
    if (!element) return;
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const items = () => [...element.querySelectorAll<HTMLElement>(focusable)];
    if (!element.contains(document.activeElement)) ((focusFirst ? items()[0] : undefined) ?? element).focus();

    const keydown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        escape.current();
        return;
      }
      if (event.key !== "Tab") return;
      const all = items();
      if (all.length === 0) return;
      const first = all[0];
      const last = all[all.length - 1];
      const inside = element.contains(document.activeElement);
      if (!inside || (event.shiftKey && document.activeElement === first)) {
        event.preventDefault();
        (event.shiftKey ? last : first).focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener("keydown", keydown);
    return () => {
      document.removeEventListener("keydown", keydown);
      if (opener?.isConnected) opener.focus();
    };
  }, [dialog, focusFirst]);
}
