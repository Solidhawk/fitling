import { useState } from "react";
import { t } from "./i18n";
import { type Tab, TabBar, tabs } from "./TabBar";

/** The five tabs of the iOS app (HomeView); each shows its large title until its screens are built. */
export function Home() {
  const [tab, setTab] = useState<Tab>("today");
  const title = tabs.find((candidate) => candidate.id === tab)?.title ?? "tab.today";
  return (
    <div className="app" data-screen="home">
      <main className="page">
        <div id={`panel-${tab}`} role="tabpanel" aria-labelledby={`tab-${tab}`}>
          <h1 className="large-title">{t(title)}</h1>
        </div>
      </main>
      <TabBar selected={tab} onSelect={setTab} />
    </div>
  );
}
