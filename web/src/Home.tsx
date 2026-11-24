import { useState } from "react";
import type { AuthService } from "./data/auth";
import { t } from "./i18n";
import { Day } from "./screens/Day";
import { Profile } from "./screens/Profile";
import { type Tab, TabBar, tabs } from "./TabBar";

/** The five tabs of the iOS app (HomeView); a tab whose screens are not built yet shows its large title. */
export function Home({ userID, auth }: { userID: string; auth: AuthService }) {
  const [tab, setTab] = useState<Tab>("today");
  const title = tabs.find((candidate) => candidate.id === tab)?.title ?? "tab.today";
  return (
    <div className="app" data-screen="home">
      <main className="page">
        <div id={`panel-${tab}`} role="tabpanel" aria-labelledby={`tab-${tab}`}>
          {tab === "today" ? (
            <Day userID={userID} />
          ) : tab === "target" ? (
            <Profile userID={userID} auth={auth} />
          ) : (
            <h1 className="large-title">{t(title)}</h1>
          )}
        </div>
      </main>
      <TabBar selected={tab} onSelect={setTab} />
    </div>
  );
}
