import type { ReactNode } from "react";

/** A grouped list on the pastel ground, as a SwiftUI Form or List in the app (groundBackground). */
export function List({ children }: { children: ReactNode }) {
  return <div className="list">{children}</div>;
}

/**
 * One section: an optional header, white rows with hairlines, an optional footnote in soft ink. `lead` sits above the
 * rows without being a heading, for a header that VoiceOver skips on iOS (accessibilityHidden).
 */
export function ListSection({ header, lead, footer, children }: { header?: ReactNode; lead?: ReactNode; footer?: ReactNode; children?: ReactNode }) {
  return (
    <section className="list-section">
      {header !== undefined && <h2 className="list-header">{header}</h2>}
      {lead}
      {children !== undefined && <div className="list-rows">{children}</div>}
      {footer !== undefined && <div className="list-footer">{footer}</div>}
    </section>
  );
}

/** A row; `as="button"` for a tappable row such as a NavigationLink, with the disclosure chevron. */
export function ListRow({
  children,
  onClick,
  chevron = false,
  disabled = false,
}: {
  children: ReactNode;
  onClick?: () => void;
  chevron?: boolean;
  disabled?: boolean;
}) {
  if (onClick) {
    return (
      <button type="button" className="list-row list-row-button" disabled={disabled} onClick={onClick}>
        <span className="list-row-content">{children}</span>
        {chevron && (
          <svg className="list-chevron" viewBox="0 0 8 14" aria-hidden="true">
            <path d="M1 1l6 6-6 6" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        )}
      </button>
    );
  }
  return <div className="list-row">{children}</div>;
}
