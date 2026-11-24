import { ChevronLeft } from "lucide-react";
import type { ReactNode } from "react";

/**
 * The navigation bar of a pushed screen: back to the previous screen with its title, this screen's title
 * inline in the middle, and room for an action on the right (NavigationStack on iOS). A sheet puts its Cancel in
 * `leading` instead of a way back.
 */
export function NavBar({
  title,
  back,
  onBack,
  leading,
  trailing,
}: {
  title: string;
  back?: string;
  onBack?: () => void;
  leading?: ReactNode;
  trailing?: ReactNode;
}) {
  return (
    <header className="nav-bar">
      <div className="nav-bar-side">
        {leading}
        {onBack && (
          <button type="button" className="nav-back" onClick={onBack}>
            <ChevronLeft aria-hidden="true" size={28} strokeWidth={2.2} />
            <span>{back}</span>
          </button>
        )}
      </div>
      <h1 className="nav-title">{title}</h1>
      <div className="nav-bar-side nav-bar-trailing">{trailing}</div>
    </header>
  );
}
