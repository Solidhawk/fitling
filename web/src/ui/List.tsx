import type { ReactNode } from "react";

/** A grouped list on the pastel ground, as a SwiftUI Form or List in the app (groundBackground). */
export function List({ children }: { children: ReactNode }) {
  return <div className="list">{children}</div>;
}

/** One section: an optional header, white rows with hairlines, an optional footnote in soft ink. */
export function ListSection({ header, footer, children }: { header?: ReactNode; footer?: ReactNode; children?: ReactNode }) {
  return (
    <section className="list-section">
      {header !== undefined && <h2 className="list-header">{header}</h2>}
      {children !== undefined && <div className="list-rows">{children}</div>}
      {footer !== undefined && <div className="list-footer">{footer}</div>}
    </section>
  );
}

/** A row; `as="button"` for a tappable row such as a NavigationLink, with the disclosure chevron. */
export function ListRow({ children, onClick, chevron = false }: { children: ReactNode; onClick?: () => void; chevron?: boolean }) {
  if (onClick) {
    return (
      <button type="button" className="list-row list-row-button" onClick={onClick}>
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
