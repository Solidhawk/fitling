import { ChevronLeft } from "lucide-react";
import type { ReactNode } from "react";

/**
 * The navigation bar of a pushed screen: back to the previous screen with its title, this screen's title
 * inline in the middle, and room for an action on the right (NavigationStack on iOS). A sheet puts its Cancel in
 * `leading` instead of a way back. `large` puts the title under the bar in large type, as a screen pushed in a
 * stack that starts with a large title (Account on Dagdoel).
 */
export function NavBar({
  title,
  back,
  onBack,
  leading,
  trailing,
  large = false,
}: {
  title: string;
  back?: string;
  onBack?: () => void;
  leading?: ReactNode;
  trailing?: ReactNode;
  large?: boolean;
}) {
  return (
    <>
      <header className={onBack ? "nav-bar nav-bar-pushed" : "nav-bar"}>
        <div className="nav-bar-side">
          {leading}
          {onBack && (
            <button type="button" className="nav-back" onClick={onBack}>
              <ChevronLeft aria-hidden="true" size={28} strokeWidth={2.2} />
              <span className="nav-back-label">{back}</span>
            </button>
          )}
        </div>
        {large ? (
          <span />
        ) : (
          <h1 className="nav-title" tabIndex={-1}>
            {title}
          </h1>
        )}
        <div className="nav-bar-side nav-bar-trailing">{trailing}</div>
      </header>
      {large && <h1 className="large-title">{title}</h1>}
    </>
  );
}
