import { ScanBarcode, Search, SquarePen } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { FitlingCore } from "../core/fitlingCore";
import { favoriteProducts, type Meal, recentProducts } from "../data/diary";
import { lookUp } from "../data/lookup";
import { type Product, productName, searchProducts } from "../data/products";
import { supabase } from "../data/supabase";
import { useHistoryStack } from "../historyStack";
import { t } from "../i18n";
import { Alert } from "../ui/Alert";
import { useDialogFocus } from "../ui/dialogFocus";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";
import { ProductRow } from "../ui/ProductRow";
import { AddProduct } from "./AddProduct";
import { Portion } from "./Portion";
import { Scan } from "./Scan";

type Step = { kind: "list" } | { kind: "portion"; product: Product } | { kind: "addProduct"; gtin?: string };

/** What a scan led to that needs the user: nobody knows the barcode, or there is no connection. */
type ScanAlert = { kind: "unknown"; gtin: string } | { kind: "unavailable" };

/**
 * Choosing what to log: search by name, recent products, favourites, a scanned barcode or an own product; then the
 * portion (LogFoodView.swift). A sheet with its own stack; swiping back goes one screen back.
 */
export function LogFood({ core, userID, meal, day, onClose }: { core: FitlingCore; userID: string; meal: Meal; day: string; onClose: () => void }) {
  const [stack, setStack] = useState<Step[]>([{ kind: "list" }]);
  const [query, setQuery] = useState("");
  const [recent, setRecent] = useState<Product[]>([]);
  const [favorites, setFavorites] = useState<Product[]>([]);
  // Both lists were read: "Nog niets gelogd" is then true when both are empty.
  const [listsRead, setListsRead] = useState(false);
  const [results, setResults] = useState<{ own: Product[]; online: Product[] }>({ own: [], online: [] });
  const [searching, setSearching] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [scanAlert, setScanAlert] = useState<ScanAlert>();
  const [failed, setFailed] = useState<string>();
  const sheet = useRef<HTMLDivElement>(null);
  const lookingUp = useRef(false);
  const step = stack[stack.length - 1];
  const push = (next: Step) => setStack((current) => [...current, next]);
  // The list counts as a screen too: Back on it closes the sheet, as swiping a sheet down on the iPhone (UNFORGET S40).
  const back = useHistoryStack(stack.length, (depth) => (depth === 0 ? onClose() : setStack((current) => current.slice(0, depth))));
  // Cancel, Escape and saving close the sheet through the history as well, so its screens leave nothing behind there;
  // once, or a second press would go back past the page under the sheet.
  const closing = useRef(false);
  const close = () => {
    if (closing.current) return;
    closing.current = true;
    history.go(-stack.length);
  };
  useDialogFocus(sheet, close);
  // The next step replaces the row that was tapped: the focus goes to its title, as a pushed screen on the iPhone and
  // each step of the onboarding, not to the page behind the sheet.
  const firstStep = useRef(true);
  useEffect(() => {
    if (firstStep.current) {
      firstStep.current = false;
      return;
    }
    sheet.current?.querySelector<HTMLElement>(".nav-title")?.focus();
  }, [step]);

  useEffect(() => {
    // Each list shows as it comes, and one that cannot be read does not hide the other. "Nog niets gelogd" only once
    // both were read: after a failed read it would not be true.
    void Promise.all([recentProducts(supabase, core).then(setRecent), favoriteProducts(supabase).then(setFavorites)]).then(
      () => setListsRead(true),
      (error: unknown) => setFailed(error instanceof Error ? error.message : "error.server"),
    );
  }, [core]);

  // Waits for a pause in typing, so every keystroke does not search online; an answer to an older term is dropped.
  useEffect(() => {
    if (query.trim() === "") {
      setResults({ own: [], online: [] });
      return;
    }
    let current = true;
    const timer = setTimeout(() => {
      setSearching(true);
      searchProducts(supabase, core, query, [...favorites, ...recent])
        .then(
          (found) => {
            if (!current) return;
            setResults(found);
            if (found.failed) setFailed(found.failed);
          },
          (error: unknown) => current && setFailed(error instanceof Error ? error.message : "error.server"),
        )
        .finally(() => current && setSearching(false));
    }, 300);
    return () => {
      current = false;
      clearTimeout(timer);
    };
  }, [query, core, favorites, recent]);

  /** A barcode from the camera or typed in (LogFoodViewModel.handleScan); while one is looked up, the camera waits. */
  async function handleScan(code: string) {
    // While an alert about the last code is open, the camera waits too.
    if (lookingUp.current || scanAlert) return;
    lookingUp.current = true;
    try {
      const result = await lookUp(supabase, core, code, new Date());
      if (result.kind === "found") {
        setScanning(false);
        push({ kind: "portion", product: result.product });
      } else if (result.kind === "notFound") {
        setScanAlert({ kind: "unknown", gtin: result.gtin });
      } else if (result.kind === "unavailable") {
        setScanAlert({ kind: "unavailable" });
      }
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    } finally {
      lookingUp.current = false;
    }
  }

  const title = t(`meal.${meal}`);
  const productSection = (key: string, products: Product[]) =>
    products.length > 0 && (
      <ListSection header={t(key)}>
        {products.map((product) => (
          <ProductRow
            key={product.id}
            name={productName(core, product)}
            brand={product.brand}
            kcal100={product.kcal100}
            unit={product.quantityUnit}
            imageURL={product.imageURL}
            onClick={() => push({ kind: "portion", product })}
          />
        ))}
      </ListSection>
    );

  return (
    <div ref={sheet} className="sheet" role="dialog" aria-modal="true" aria-label={title} tabIndex={-1} data-screen="logFood">
      {step.kind === "portion" && (
        <Portion core={core} userID={userID} product={step.product} meal={meal} day={day} back={title} onBack={back} onSaved={close} />
      )}
      {step.kind === "addProduct" && (
        <AddProduct
          core={core}
          userID={userID}
          gtin={step.gtin}
          back={title}
          onBack={back}
          onSaved={(product) => setStack((current) => [...current.slice(0, -1), { kind: "portion", product }])}
        />
      )}
      {step.kind === "list" && (
        <>
          <NavBar
            title={title}
            leading={
              <button type="button" className="nav-back nav-action" onClick={close}>
                {t("common.cancel")}
              </button>
            }
          />
          <div className="search-bar">
            <Search aria-hidden="true" size={18} strokeWidth={2.2} />
            <input
              type="search"
              className="search-field"
              placeholder={t("log.search.prompt")}
              aria-label={t("log.search.prompt")}
              data-testid="log.search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
            />
          </div>
          <List>
            {query.trim() === "" ? (
              <>
                <ListSection>
                  <ListRow onClick={() => setScanning(true)}>
                    <span className="inline-action" data-testid="log.scan">
                      <ScanBarcode aria-hidden="true" size={20} strokeWidth={2.2} />
                      <span>{t("log.scan")}</span>
                    </span>
                  </ListRow>
                  <ListRow onClick={() => push({ kind: "addProduct" })}>
                    <span className="inline-action" data-testid="log.ownProduct">
                      <SquarePen aria-hidden="true" size={20} strokeWidth={2.2} />
                      <span>{t("log.ownProduct")}</span>
                    </span>
                  </ListRow>
                </ListSection>
                {productSection("log.favorites", favorites)}
                {productSection("log.recent", recent)}
                {listsRead && favorites.length === 0 && recent.length === 0 && <ListSection footer={t("log.empty")} />}
              </>
            ) : (
              <>
                {productSection("log.results.device", results.own)}
                {productSection("log.results.online", results.online)}
                {searching ? (
                  <div className="loading search-loading">
                    <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
                  </div>
                ) : (
                  results.own.length === 0 &&
                  results.online.length === 0 && (
                    <ListSection footer={t("log.results.none")}>
                      <ListRow onClick={() => push({ kind: "addProduct" })}>{t("log.ownProduct")}</ListRow>
                    </ListSection>
                  )
                )}
              </>
            )}
          </List>
        </>
      )}
      {scanning && <Scan onCode={(code) => void handleScan(code)} onCancel={() => setScanning(false)} />}
      {scanAlert?.kind === "unknown" && (
        <Alert
          title={t("scan.unknown.title")}
          message={t("scan.unknown.body")}
          actions={[
            {
              label: t("scan.unknown.add"),
              onSelect: () => {
                setScanning(false);
                setScanAlert(undefined);
                push({ kind: "addProduct", gtin: scanAlert.gtin });
              },
            },
          ]}
          onClose={() => setScanAlert(undefined)}
        />
      )}
      {scanAlert?.kind === "unavailable" && (
        <Alert title={t("common.connection.title")} message={t("scan.offline.body")} onClose={() => setScanAlert(undefined)} />
      )}
      {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
    </div>
  );
}
