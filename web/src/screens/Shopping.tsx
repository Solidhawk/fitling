import { Circle, CircleCheck, CookingPot, PlusCircle, ShoppingCart, UserPlus, Users } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { FitlingCore, MenuInput, ShoppingOverview } from "../core/fitlingCore";
import {
  addItem,
  applyRefill,
  clearChecked,
  createInvite,
  ensureList,
  joinList,
  leaveList,
  loadRecipeIngredients,
  loadShopping,
  removeItem,
  setFavoriteSupermarket,
  type ShoppingRows,
  toggleItem,
} from "../data/shopping";
import { supabase } from "../data/supabase";
import { today } from "../day";
import { t } from "../i18n";
import { amountText } from "../menu/texts";
import { confirmedOffers, confirmOffers, euros, shopList, validUntil } from "../shopping/texts";
import { ActionSheet } from "../ui/ActionSheet";
import { Alert } from "../ui/Alert";
import { FormSheet } from "../ui/FormSheet";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";
import { SwipeRow } from "../ui/SwipeRow";

/** PrijsProfeet's terms ask for a visible credit with a link on every screen with their data. */
const offerSource = "https://www.prijsprofeet.nl";

type Item = ShoppingOverview["items"][number];

/**
 * The shopping list, opened from the menu tab (ShoppingListView.swift): the items in the order of a walk through the
 * shop, what the week menu needs, the offers of the user's supermarkets, and sharing the list with a code. It reads
 * the list again when it opens and when the app comes back, as the iPhone syncs then.
 */
export function Shopping({ core, userID, menu, onBack }: { core: FitlingCore; userID: string; menu: MenuInput; onBack: () => void }) {
  const [rows, setRows] = useState<ShoppingRows>();
  const [confirmed, setConfirmed] = useState(confirmedOffers);
  const [failed, setFailed] = useState<string>();
  const [sharingProblem, setSharingProblem] = useState<string>();
  const [newItem, setNewItem] = useState("");
  const [inviteCode, setInviteCode] = useState<string>();
  const [joining, setJoining] = useState(false);
  const [choosingShops, setChoosingShops] = useState(false);
  const [confirmingLeave, setConfirmingLeave] = useState(false);
  // One fill from the menu at a time: a double tap puts the week on the list once.
  const filling = useRef(false);
  const listID = useRef<string>(undefined);

  /** The list again; which list it is is asked again only when it may have changed (opening, joining, leaving). */
  const reload = useCallback(
    async (findList = false) => {
      try {
        if (findList || !listID.current) {
          listID.current = (await ensureList(supabase, userID, t("shopping.title"), t("shopping.member.default"), new Date())).id;
        }
        setRows(await loadShopping(supabase, listID.current, today(), new Date()));
      } catch (error) {
        setFailed(error instanceof Error ? error.message : "error.server");
      }
    },
    [userID],
  );

  useEffect(() => {
    void reload(true);
    // Back in the app: another device may have changed the list, or who is on it.
    const again = () => document.visibilityState === "visible" && void reload(true);
    document.addEventListener("visibilitychange", again);
    return () => document.removeEventListener("visibilitychange", again);
  }, [reload]);

  const overview = useMemo(
    () =>
      rows &&
      core.shoppingOverview({
        shopping: {
          today: today(),
          items: rows.items,
          offers: rows.offers,
          supermarkets: rows.supermarkets,
          favoriteSupermarketIDs: rows.favoriteSupermarketIDs,
          confirmedOfferIDs: confirmed,
        },
      }),
    [core, rows, confirmed],
  );

  async function act(work: () => Promise<void>, findList = false) {
    try {
      await work();
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
    await reload(findList);
  }

  function add() {
    const item = core.shoppingNewItem({ text: newItem }).item;
    if (!item || !rows) return;
    setNewItem("");
    void act(() => addItem(supabase, userID, rows.list.id, item, "manual", new Date()));
  }

  /** What this week's menu needs (ShoppingViewModel.fillFromMenu). */
  function fillFromMenu() {
    if (!rows || filling.current) return;
    filling.current = true;
    void act(async () => {
      const ingredients = await loadRecipeIngredients(supabase, menu.entries.map((entry) => entry.recipeID));
      const change = core.shoppingRefill({
        shopping: { today: today(), items: rows.items, offers: [], supermarkets: [], favoriteSupermarketIDs: [], confirmedOfferIDs: [] },
        menu,
        ingredients,
      });
      await applyRefill(supabase, userID, rows.list.id, change, new Date());
    }).finally(() => {
      filling.current = false;
    });
  }

  async function invite() {
    if (!rows) return;
    setSharingProblem(undefined);
    try {
      setInviteCode(await createInvite(supabase, rows.list.id));
    } catch (error) {
      setSharingProblem(error instanceof Error ? error.message : "error.server");
    }
  }

  async function join(code: string, name: string): Promise<boolean> {
    setSharingProblem(undefined);
    try {
      await joinList(supabase, code, name.trim() === "" ? t("shopping.member.default") : name);
      await reload(true);
      return true;
    } catch (error) {
      setSharingProblem(error instanceof Error ? error.message : "error.server");
      return false;
    }
  }

  function leave() {
    setConfirmingLeave(false);
    if (!rows) return;
    void act(async () => {
      try {
        await leaveList(supabase, rows.list.id, userID);
      } catch (error) {
        setSharingProblem(error instanceof Error ? error.message : "error.server");
      }
    }, true);
  }

  if (!rows || !overview) {
    return (
      <div className="tab-page pushed" data-page="shopping">
        <NavBar title={t("shopping.title")} back={t("menu.title")} onBack={onBack} large />
        <div className="loading tab-loading" aria-busy="true">
          <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
        </div>
        {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
      </div>
    );
  }

  const canAdd = newItem.trim() !== "";
  return (
    <div className="tab-page pushed" data-page="shopping">
      <NavBar title={rows.list.name} back={t("menu.title")} onBack={onBack} large />
      <List>
        <ListSection>
          <ListRow>
            <form
              className="shopping-add"
              onSubmit={(event) => {
                event.preventDefault();
                add();
              }}
            >
              <input
                className="text-field"
                enterKeyHint="done"
                placeholder={t("shopping.add.placeholder")}
                aria-label={t("shopping.add.placeholder")}
                data-testid="shopping.add.field"
                value={newItem}
                onChange={(event) => setNewItem(event.target.value)}
              />
              <button type="submit" className="icon-button shopping-add-button" aria-label={t("shopping.add")} disabled={!canAdd}>
                <PlusCircle aria-hidden="true" size={26} strokeWidth={2} />
              </button>
            </form>
          </ListRow>
          <ListRow onClick={fillFromMenu}>
            <span className="icon-label" data-testid="shopping.fromMenu">
              <CookingPot aria-hidden="true" size={22} strokeWidth={2} />
              <span>{t("shopping.fromMenu")}</span>
            </span>
          </ListRow>
        </ListSection>

        {overview.items.length === 0 ? (
          <section className="list-section">
            <p className="list-footer shopping-empty">{t("shopping.empty")}</p>
          </section>
        ) : (
          <ListSection>
            {overview.items.map((item) => (
              <SwipeRow key={item.id} bare deleteLabel={t("day.delete")} onDelete={() => void act(() => removeItem(supabase, userID, item.id, new Date()))}>
                <ItemRow item={item} onToggle={() => void act(() => toggleItem(supabase, userID, item, new Date()))} />
              </SwipeRow>
            ))}
            {overview.items.some((item) => item.isChecked) && (
              <ListRow onClick={() => void act(() => clearChecked(supabase, userID, rows.list.id, new Date()))}>
                <span className="destructive" data-testid="shopping.clearChecked">
                  {t("shopping.clearChecked")}
                </span>
              </ListRow>
            )}
          </ListSection>
        )}

        <ListSection
          header={t("shopping.offers")}
          footer={
            <>
              <span>{t("shopping.offers.footer")}</span>
              <a className="source-link" href={offerSource} target="_blank" rel="noreferrer">
                {t("shopping.offers.source")}
              </a>
            </>
          }
        >
          {overview.totals.map((total) => (
            <div key={total.supermarketID} className="list-row" data-testid={`shopping.total.${total.supermarketID}`}>
              <span className="labeled">
                <span>{total.name}</span>
                <span className="shopping-price">
                  <span className="value">{euros(total.totalCents)}</span>
                  {total.itemsWithoutPrice > 0 && <span className="caption secondary">{t("shopping.withoutPrice %lld", total.itemsWithoutPrice)}</span>}
                </span>
              </span>
            </div>
          ))}
          {overview.questions.slice(0, 5).map((question) => (
            <div key={question.id} className="list-row" data-testid="shopping.question">
              <span className="row-stack shopping-question">
                <span className="footnote">{t("shopping.uncertain %@ %@", question.offerTitle, question.itemName)}</span>
                <span className="caption secondary">{shopList(question.supermarketNames)}</span>
              </span>
              <button
                type="button"
                className="inline-action strong"
                onClick={() => {
                  confirmOffers(question.offerIDs);
                  setConfirmed(confirmedOffers());
                }}
              >
                {t("shopping.confirm")}
              </button>
            </div>
          ))}
          <ListRow onClick={() => setChoosingShops(true)}>
            <span className="icon-label" data-testid="shopping.shops">
              <ShoppingCart aria-hidden="true" size={22} strokeWidth={2} />
              <span>{t("shopping.shops")}</span>
            </span>
          </ListRow>
        </ListSection>

        <ListSection header={t("shopping.members")} footer={t(sharingProblem === "error.network" ? "common.connection.body" : (sharingProblem ?? "shopping.members.footer"))}>
          {rows.members.map((member) => (
            <div key={member.userID} className="list-row" data-testid="shopping.member">
              <span className="labeled">
                <span>{member.displayName}</span>
                {member.role === "owner" && <span className="footnote secondary">{t("shopping.owner")}</span>}
              </span>
            </div>
          ))}
          <ListRow onClick={() => void invite()}>
            <span className="icon-label" data-testid="shopping.invite">
              <UserPlus aria-hidden="true" size={22} strokeWidth={2} />
              <span>{t("shopping.invite")}</span>
            </span>
          </ListRow>
          <ListRow onClick={() => setJoining(true)}>
            <span className="icon-label" data-testid="shopping.join">
              <Users aria-hidden="true" size={22} strokeWidth={2} />
              <span>{t("shopping.join")}</span>
            </span>
          </ListRow>
          {rows.members.length > 1 && (
            <ListRow onClick={() => setConfirmingLeave(true)}>
              <span className="destructive" data-testid="shopping.leave">
                {t("shopping.leave")}
              </span>
            </ListRow>
          )}
        </ListSection>
      </List>

      {inviteCode && (
        <Alert
          title={t("shopping.invite.title")}
          message={t("shopping.invite.body %@", inviteCode)}
          cancelLabel={t("common.ok")}
          onClose={() => setInviteCode(undefined)}
          actions={[
            {
              label: t("shopping.invite.copy"),
              onSelect: () => {
                void navigator.clipboard?.writeText(inviteCode).catch(() => undefined);
                setInviteCode(undefined);
              },
            },
          ]}
        />
      )}
      {joining && <JoinSheet onJoin={join} onClose={() => setJoining(false)} />}
      {choosingShops && (
        <SupermarketPicker
          rows={rows}
          onChange={(supermarketID, favorite) => void act(() => setFavoriteSupermarket(supabase, userID, supermarketID, favorite, new Date()))}
          onDone={() => setChoosingShops(false)}
        />
      )}
      {confirmingLeave && (
        <ActionSheet
          title={t("shopping.leave.title")}
          onCancel={() => setConfirmingLeave(false)}
          actions={[{ label: t("shopping.leave"), destructive: true, onSelect: leave }]}
        />
      )}
      {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
    </div>
  );
}

/** One item: tapping checks it off; its amount, and for what is not in the basket yet its cheapest offer. */
function ItemRow({ item, onToggle }: { item: Item; onToggle: () => void }) {
  return (
    <button
      type="button"
      className="list-row list-row-button shopping-item"
      aria-pressed={item.isChecked}
      data-testid={`shopping.item.${item.name}`}
      onClick={onToggle}
    >
      {item.isChecked ? (
        <CircleCheck className="shopping-check" aria-hidden="true" size={24} strokeWidth={2} fill="currentColor" stroke="var(--card)" />
      ) : (
        <Circle className="shopping-check" aria-hidden="true" size={24} strokeWidth={2} />
      )}
      <span className="row-stack shopping-item-text">
        <span className={item.isChecked ? "shopping-done" : undefined}>{item.name}</span>
        {item.quantity !== undefined && item.unit && <span className="footnote secondary tabular">{amountText(item.quantity, item.unit)}</span>}
      </span>
      {item.offer && (
        <span className="shopping-price" data-testid={`shopping.offer.${item.name}`}>
          <span className="value">{euros(item.offer.priceCents)}</span>
          <span className="caption secondary">{item.offer.supermarketName}</span>
          <span className="caption secondary">{validUntil(item.offer.validTo)}</span>
        </span>
      )}
    </button>
  );
}

/** A code from someone else, and the name the other members will see (JoinListSheet). */
function JoinSheet({ onJoin, onClose }: { onJoin: (code: string, name: string) => Promise<boolean>; onClose: () => void }) {
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [working, setWorking] = useState(false);
  const canJoin = !working && code.trim().length >= 6 && name.trim() !== "";
  return (
    <FormSheet
      title={t("shopping.join")}
      saveLabel={t("shopping.join.confirm")}
      canSave={canJoin}
      onCancel={onClose}
      onSave={() => {
        setWorking(true);
        void onJoin(code, name).then((joined) => {
          setWorking(false);
          if (joined) onClose();
        });
      }}
    >
      <ListSection footer={t("shopping.join.footer")}>
        <ListRow>
          <input
            className="text-field"
            autoCapitalize="characters"
            autoCorrect="off"
            spellCheck={false}
            placeholder={t("shopping.join.code")}
            aria-label={t("shopping.join.code")}
            data-testid="shopping.join.code"
            value={code}
            onChange={(event) => setCode(event.target.value)}
          />
        </ListRow>
        <ListRow>
          <input
            className="text-field"
            placeholder={t("shopping.join.name")}
            aria-label={t("shopping.join.name")}
            data-testid="shopping.join.name"
            value={name}
            onChange={(event) => setName(event.target.value)}
          />
        </ListRow>
      </ListSection>
    </FormSheet>
  );
}

/** The supermarkets whose offers are shown; every change is saved at once (SupermarketPicker). */
function SupermarketPicker({
  rows,
  onChange,
  onDone,
}: {
  rows: ShoppingRows;
  onChange: (supermarketID: string, favorite: boolean) => void;
  onDone: () => void;
}) {
  // Shown at once; stored in the background, as each change is saved on iOS.
  const [favorites, setFavorites] = useState(() => new Set(rows.favoriteSupermarketIDs));
  return (
    <FormSheet title={t("shopping.shops")} saveLabel={t("common.ok")} onSave={onDone} onCancel={onDone} cancel={false}>
      {rows.supermarkets.length === 0 ? (
        <section className="list-section">
          <p className="list-footer">{t("shopping.shops.empty")}</p>
        </section>
      ) : (
        <ListSection>
          {rows.supermarkets.map((shop) => (
            <ListRow key={shop.id}>
              <label className="toggle-row">
                <span>{shop.name}</span>
                <input
                  type="checkbox"
                  role="switch"
                  className="switch"
                  data-testid={`shopping.shop.${shop.id}`}
                  checked={favorites.has(shop.id)}
                  onChange={(event) => {
                    const on = event.target.checked;
                    setFavorites((shown) => {
                      const next = new Set(shown);
                      if (on) next.add(shop.id);
                      else next.delete(shop.id);
                      return next;
                    });
                    onChange(shop.id, on);
                  }}
                />
              </label>
            </ListRow>
          ))}
        </ListSection>
      )}
    </FormSheet>
  );
}
