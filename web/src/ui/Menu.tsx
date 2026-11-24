import { useEffect, useRef, useState } from "react";

/** A button that opens a short list of actions under it, as a Menu in the toolbar on iOS. */
export function Menu({ label, items, testID }: { label: string; items: { label: string; onSelect: () => void }[]; testID?: string }) {
  const [open, setOpen] = useState(false);
  const menu = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    menu.current?.querySelector<HTMLButtonElement>("[role=menuitem]")?.focus();
    const close = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      setOpen(false);
      button.current?.focus();
    };
    window.addEventListener("keydown", close);
    return () => window.removeEventListener("keydown", close);
  }, [open]);

  return (
    <span className="menu">
      <button
        ref={button}
        type="button"
        className="nav-back nav-action"
        aria-haspopup="menu"
        aria-expanded={open}
        data-testid={testID}
        onClick={() => setOpen(!open)}
      >
        {label}
      </button>
      {open && (
        <>
          <span className="menu-backdrop" aria-hidden="true" onClick={() => setOpen(false)} />
          <div ref={menu} className="menu-items" role="menu" aria-label={label}>
            {items.map((item) => (
              <button
                key={item.label}
                type="button"
                role="menuitem"
                className="menu-item"
                onClick={() => {
                  setOpen(false);
                  item.onSelect();
                }}
              >
                {item.label}
              </button>
            ))}
          </div>
        </>
      )}
    </span>
  );
}
