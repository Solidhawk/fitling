import { type ReactNode, useEffect, useRef, useState } from "react";

/**
 * A button that opens a short list of actions under it, as a Menu in the toolbar on iOS. With `icon` the button
 * shows it instead of its label (which a screen reader still says); a destructive item is red, as role: .destructive.
 */
export function Menu({
  label,
  items,
  testID,
  icon,
}: {
  label: string;
  items: { label: string; onSelect: () => void; destructive?: boolean }[];
  testID?: string;
  icon?: ReactNode;
}) {
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
        className={icon ? "nav-back nav-action icon-button" : "nav-back nav-action"}
        aria-label={icon ? label : undefined}
        aria-haspopup="menu"
        aria-expanded={open}
        data-testid={testID}
        onClick={() => setOpen(!open)}
      >
        {icon ?? label}
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
                className={item.destructive ? "menu-item destructive" : "menu-item"}
                onClick={() => {
                  setOpen(false);
                  // The sheet this opens gives the focus back here when it closes.
                  button.current?.focus();
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
