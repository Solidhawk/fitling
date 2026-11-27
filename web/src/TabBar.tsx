import { CookingPot, Dumbbell, type LucideIcon, PieChart, Smile, Utensils } from "lucide-react";
import type { KeyboardEvent } from "react";
import { t } from "./i18n";

export type Tab = "today" | "training" | "menu" | "partner" | "target";

/** The tabs in the order and with the titles of the iOS app; the icons are the free counterparts of its SF Symbols. */
export const tabs: { id: Tab; title: string; icon: LucideIcon }[] = [
  { id: "today", title: "tab.today", icon: Utensils },
  { id: "training", title: "training.title", icon: Dumbbell },
  { id: "menu", title: "menu.title", icon: CookingPot },
  { id: "partner", title: "partner.title", icon: Smile },
  { id: "target", title: "profile.title", icon: PieChart },
];

/**
 * The tab bar as a tablist (WAI-ARIA tabs): the arrow keys go to the next tab and open it, Home and End to the first
 * and the last; Tab reaches only the open one.
 */
export function TabBar({ selected, onSelect }: { selected: Tab; onSelect: (tab: Tab) => void }) {
  function keyDown(event: KeyboardEvent<HTMLDivElement>) {
    // With a modifier the arrow belongs to the browser or the system (Alt+Left is Back). A key held down moves one tab,
    // not through every tab, each of which would open on the way.
    if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    if (event.repeat) {
      event.preventDefault();
      return;
    }
    const index = tabs.findIndex(({ id }) => `tab-${id}` === (event.target as HTMLElement).id);
    if (index < 0) return;
    const next = { ArrowRight: index + 1, ArrowLeft: index - 1, Home: 0, End: tabs.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    const { id } = tabs[(next + tabs.length) % tabs.length];
    onSelect(id);
    document.getElementById(`tab-${id}`)?.focus();
  }

  return (
    <nav className="tab-bar-frame">
      <div className="tab-bar" role="tablist" onKeyDown={keyDown}>
      {tabs.map(({ id, title, icon: Icon }) => (
        <button
          key={id}
          id={`tab-${id}`}
          type="button"
          role="tab"
          aria-selected={id === selected}
          aria-controls={`panel-${id}`}
          tabIndex={id === selected ? 0 : -1}
          className="tab"
          onClick={() => onSelect(id)}
        >
          <Icon aria-hidden="true" size={26} strokeWidth={id === selected ? 2.4 : 1.8} />
          <span>{t(title)}</span>
        </button>
      ))}
      </div>
    </nav>
  );
}
