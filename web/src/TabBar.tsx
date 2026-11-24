import { CookingPot, Dumbbell, type LucideIcon, PieChart, Smile, Utensils } from "lucide-react";
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

export function TabBar({ selected, onSelect }: { selected: Tab; onSelect: (tab: Tab) => void }) {
  return (
    <nav className="tab-bar" role="tablist">
      {tabs.map(({ id, title, icon: Icon }) => (
        <button
          key={id}
          id={`tab-${id}`}
          type="button"
          role="tab"
          aria-selected={id === selected}
          aria-controls={`panel-${id}`}
          className="tab"
          onClick={() => onSelect(id)}
        >
          <Icon aria-hidden="true" size={26} strokeWidth={id === selected ? 2.4 : 1.8} />
          <span>{t(title)}</span>
        </button>
      ))}
    </nav>
  );
}
