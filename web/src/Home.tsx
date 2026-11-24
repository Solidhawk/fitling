import { useCallback, useRef, useState } from "react";
import type { FitlingCore, PartnerEvent } from "./core/fitlingCore";
import type { AuthService } from "./data/auth";
import { advancePartner, type Partner as StoredPartner } from "./data/creature";
import { supabase } from "./data/supabase";
import { today } from "./day";
import { t } from "./i18n";
import { Day } from "./screens/Day";
import { Partner } from "./screens/Partner";
import { Profile } from "./screens/Profile";
import { Training } from "./screens/Training";
import { type Tab, TabBar, tabs } from "./TabBar";

/**
 * The five tabs of the iOS app (HomeView); a tab whose screens are not built yet shows its large title. Finished days
 * are folded into the partner when Vandaag or the partner tab loads (also when the app comes back), one fold at a
 * time; what that brought is kept here until the partner tab has shown it (PartnerViewModel.news).
 */
export function Home({ userID, auth }: { userID: string; auth: AuthService }) {
  const [tab, setTab] = useState<Tab>("today");
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
          ) : tab === "partner" ? (
            <Partner userID={userID} advance={advance} news={news} onNewsSeen={() => setNews([])} />
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
