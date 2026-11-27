import { useCallback, useEffect, useRef, useState } from "react";
import type { FitlingCore, PartnerEvent } from "./core/fitlingCore";
import type { AuthService } from "./data/auth";
import { advancePartner, type Partner as StoredPartner } from "./data/creature";
import { supabase } from "./data/supabase";
import { today } from "./day";
import { t } from "./i18n";
import { Day } from "./screens/Day";
import { Menu } from "./screens/Menu";
import { Partner } from "./screens/Partner";
import { Profile } from "./screens/Profile";
import { Training } from "./screens/Training";
import { type Tab, TabBar, tabs } from "./TabBar";

/** The tab the address names (#menu), so a reload opens it again; anything else there (a sign-in link) is no tab. */
function tabInAddress(): Tab | undefined {
  const named = location.hash.slice(1);
  return tabs.find((candidate) => candidate.id === named)?.id;
}

/** The address names `tab`: replaced, not pushed, so Back goes through a tab's screens and not through the tabs. */
function showInAddress(tab: Tab) {
  if (location.hash !== `#${tab}`) history.replaceState(history.state, "", `#${tab}`);
}

/**
 * The five tabs of the iOS app (HomeView); a tab whose screens are not built yet shows its large title. Finished days
 * are folded into the partner when Vandaag or the partner tab loads (also when the app comes back), one fold at a
 * time; what that brought is kept here until the partner tab has shown it (PartnerViewModel.news).
 */
export function Home({ userID, auth }: { userID: string; auth: AuthService }) {
  const [tab, setTab] = useState<Tab>(() => tabInAddress() ?? "today");
  // Back to an entry made on another tab brings that tab's address along; the address keeps naming the open one.
  useEffect(() => {
    const onPop = () => showInAddress(tab);
    addEventListener("popstate", onPop);
    return () => removeEventListener("popstate", onPop);
  }, [tab]);
  const select = (next: Tab) => {
    setTab(next);
    showInAddress(next);
  };
  const [news, setNews] = useState<PartnerEvent[]>([]);
  const folding = useRef<Promise<StoredPartner | undefined>>(undefined);
  const advance = useCallback(
    (core: FitlingCore) => {
      folding.current ??= advancePartner(supabase, core, userID, today(), new Date())
        .then(({ partner, events }) => {
          if (events.length > 0) setNews((shown) => [...shown, ...events]);
          return partner;
        })
        .finally(() => {
          folding.current = undefined;
        });
      return folding.current;
    },
    [userID],
  );
  const title = tabs.find((candidate) => candidate.id === tab)?.title ?? "tab.today";
  return (
    <div className="app" data-screen="home">
      <main className="page">
        <div id={`panel-${tab}`} role="tabpanel" aria-labelledby={`tab-${tab}`}>
          {tab === "today" ? (
            <Day userID={userID} advance={advance} />
          ) : tab === "training" ? (
            <Training userID={userID} />
          ) : tab === "menu" ? (
            <Menu userID={userID} />
          ) : tab === "partner" ? (
            <Partner userID={userID} advance={advance} news={news} onNewsSeen={() => setNews([])} />
          ) : tab === "target" ? (
            <Profile userID={userID} auth={auth} />
          ) : (
            <h1 className="large-title">{t(title)}</h1>
          )}
        </div>
      </main>
      <TabBar selected={tab} onSelect={select} />
    </div>
  );
}
