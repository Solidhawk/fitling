import { useEffect, useState } from "react";
import { deleteAccount } from "../data/account";
import type { AuthService } from "../data/auth";
import { deliver, exportFiles, exportTables, fetchTables, type Table } from "../data/export";
import { supabase } from "../data/supabase";
import { t } from "../i18n";
import { ActionSheet } from "../ui/ActionSheet";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";

type Opens = "about" | "delete";

function message(key: string | undefined) {
  return key ? <span className="message">{t(key)}</span> : undefined;
}

/** Export, About, signing out and deleting the account (AccountView.swift). */
export function Account({ auth, onBack, onOpen }: { auth: AuthService; onBack: () => void; onOpen: (page: Opens) => void }) {
  const [exportFailed, setExportFailed] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [prepared, setPrepared] = useState<Table[]>();
  const [working, setWorking] = useState(false);
  const [messageKey, setMessageKey] = useState<string>();

  // Read when the screen opens: Safari opens the share sheet only straight from a tap, not after a minute of loading.
  useEffect(() => {
    let current = true;
    fetchTables(supabase).then(
      (rows) => current && setPrepared(exportTables(rows)),
      () => undefined,
    );
    return () => {
      current = false;
    };
  }, []);

  async function exportData() {
    setExporting(true);
    try {
      const exported = prepared ?? exportTables(await fetchTables(supabase));
      await deliver(exportFiles(exported, new Date()));
      setExportFailed(false);
    } catch {
      setExportFailed(true);
    } finally {
      setExporting(false);
    }
  }

  async function signOut() {
    setWorking(true);
    setMessageKey(undefined);
    try {
      await auth.signOut();
    } catch (error) {
      setMessageKey(error instanceof Error ? error.message : "error.server");
      setWorking(false);
    }
  }

  return (
    <div className="tab-page pushed" data-page="account">
      <NavBar title={t("account.title")} back={t("profile.title")} onBack={onBack} large />
      <List>
        <ListSection footer={<span className="message">{t(exportFailed ? "account.export.failed" : "account.export.footer")}</span>}>
          <ListRow onClick={() => void exportData()} disabled={exporting}>
            {t("account.export")}
          </ListRow>
        </ListSection>
        <ListSection>
          <ListRow onClick={() => onOpen("about")} chevron>
            {t("account.about")}
          </ListRow>
        </ListSection>
        <ListSection footer={message(messageKey)}>
          <ListRow onClick={() => void signOut()} disabled={working}>
            {t("account.signOut")}
          </ListRow>
        </ListSection>
        <ListSection>
          <ListRow onClick={() => onOpen("delete")} chevron>
            {t("account.delete")}
          </ListRow>
        </ListSection>
      </List>
    </div>
  );
}

/** Deleting is final, so it asks once more (DeleteAccountView). The web has no Sign in with Apple. */
export function DeleteAccount({ auth, onBack }: { auth: AuthService; onBack: () => void }) {
  const [confirming, setConfirming] = useState(false);
  const [working, setWorking] = useState(false);
  const [messageKey, setMessageKey] = useState<string>();

  async function remove() {
    setConfirming(false);
    setWorking(true);
    setMessageKey(undefined);
    try {
      await deleteAccount(supabase, auth);
    } catch (error) {
      setMessageKey(error instanceof Error ? error.message : "error.server");
      setWorking(false);
    }
  }

  return (
    <div className="tab-page pushed" data-page="deleteAccount">
      <NavBar title={t("account.delete")} back={t("account.title")} onBack={onBack} large />
      <List>
        <ListSection>
          <ListRow>{t("account.delete.body")}</ListRow>
        </ListSection>
        <ListSection footer={message(messageKey)}>
          <button type="button" className="list-row list-row-button destructive" disabled={working} onClick={() => setConfirming(true)}>
            {t("account.delete.confirm")}
          </button>
        </ListSection>
      </List>
      {confirming && (
        <ActionSheet
          title={t("account.delete")}
          message={t("account.delete.body")}
          actions={[{ label: t("account.delete.confirm"), destructive: true, onSelect: () => void remove() }]}
          onCancel={() => setConfirming(false)}
        />
      )}
    </div>
  );
}

/** `name` is the source's own name, the same in every language. */
const sources: [key: string, name: string, url: string][] = [
  ["account.about.off", "Open Food Facts", "https://world.openfoodfacts.org"],
  ["account.about.usda", "USDA FoodData Central", "https://fdc.nal.usda.gov"],
  ["account.about.prijsprofeet", "PrijsProfeet", "https://www.prijsprofeet.nl"],
  ["account.about.everkinetic", "Everkinetic", "https://github.com/everkinetic/data"],
];

/** Where the data, drawings and photos in the app come from (AboutView.swift, RISKS R-02). */
export function About({ onBack }: { onBack: () => void }) {
  return (
    <div className="tab-page pushed" data-page="about">
      <NavBar title={t("account.about")} back={t("account.title")} onBack={onBack} large />
      <List>
        <ListSection header={t("account.about.sources")}>
          {sources.map(([key, name, url]) => (
            <ListRow key={key}>
              <span className="source">
                <span>{t(key)}</span>
                {/* A line of footnote is far below the 44 points a finger needs; the name, not the address, is read out. */}
                <a className="source-link" href={url} target="_blank" rel="noreferrer" aria-label={t("account.about.website %@", name)}>
                  {new URL(url).host}
                </a>
              </span>
            </ListRow>
          ))}
          <ListRow>{t("account.about.photos")}</ListRow>
        </ListSection>
      </List>
    </div>
  );
}
