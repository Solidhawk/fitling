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
  type ListRows,
  loadList,
  loadOffers,
  loadRecipeIngredients,
  type OfferRows,
  removeItem,
  setFavoriteSupermarket,
  toggleItem,
} from "../data/shopping";
import { supabase } from "../data/supabase";
import { today } from "../day";
import { t } from "../i18n";
import { amountText } from "../menu/texts";
import { confirmedOffers, confirmOffers, euros, rememberedList, rememberList, shopList, validUntil } from "../shopping/texts";
import { limitedText } from "../text";
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
 * the list again when it opens and when the app comes back, as the iPhone syncs then; the offers (thousands of rows)
 * only then and when the supermarkets change.
 */
export function Shopping({ core, userID, menu, onBack }: { core: FitlingCore; userID: string; menu: MenuInput; onBack: () => void }) {
  const [list, setList] = useState<ListRows>();
  const [offers, setOffers] = useState<OfferRows>();
  const [confirmed, setConfirmed] = useState(confirmedOffers);
  const [failed, setFailed] = useState<string>();
  const [sharingProblem, setSharingProblem] = useState<string>();
  const [newItem, setNewItem] = useState("");
  const [inviteCode, setInviteCode] = useState<string>();
  const [joining, setJoining] = useState(false);
  const [choosingShops, setChoosingShops] = useState(false);
  const [confirmingLeave, setConfirmingLeave] = useState(false);
  const [joinProblem, setJoinProblem] = useState<string>();
  // One fill from the menu at a time: a double tap puts the week on the list once.
  const filling = useRef(false);
  const listID = useRef<string>(undefined);
  // One search for the list at a time: two at the first opening would each make a list.
  const finding = useRef<Promise<string>>(undefined);
  // Only the newest read is shown: an older answer that arrives later never overwrites it.
  const reads = useRef(0);

  /** Which list it is: the one remembered on this device while the user can see it, else the first (ensureList). */
  const findList = useCallback(() => {
    finding.current ??= ensureList(supabase, userID, t("shopping.title"), t("shopping.member.default"), new Date(), rememberedList(userID))
      .then((found) => {
        rememberList(userID, found.id);
        listID.current = found.id;
        return found.id;
      })
      .finally(() => {
        finding.current = undefined;
      });
    return finding.current;
  }, [userID]);

  /** The list again; which list it is is asked again only when it may have changed (opening, joining, leaving). */
  const reloadList = useCallback(
    async (findAgain = false) => {
      const read = ++reads.current;
      try {
        const id = findAgain || !listID.current ? await findList() : listID.current;
        const rows = await loadList(supabase, id);
        if (read === reads.current) setList(rows);
      } catch (error) {
        setFailed(error instanceof Error ? error.message : "error.server");
      }
    },
    [findList],
  );

  const reloadOffers = useCallback(async () => {
    try {
      setOffers(await loadOffers(supabase, today(), new Date()));
    } catch (error) {
      // The offers are the list's extra: the list shows without them, with the message, so an empty choice of shops
      // or a favourite that did not come back is not taken for the truth. The next visit reads them again.
      setOffers((shown) => shown ?? { supermarkets: [], favoriteSupermarketIDs: [], offers: [] });
      setFailed(error instanceof Error ? error.message : "error.server");
    }
  }, []);

  useEffect(() => {
    void reloadList(true);
    void reloadOffers();
    // Back in the app: another device may have changed the list, or who is on it.
    const again = () => {
      if (document.visibilityState !== "visible") return;
      void reloadList(true);
      void reloadOffers();
    };
    document.addEventListener("visibilitychange", again);
    return () => document.removeEventListener("visibilitychange", again);
  }, [reloadList, reloadOffers]);

  const overview = useMemo(
    () =>
      list &&
      offers &&
      core.shoppingOverview({
        shopping: {
          today: today(),
          items: list.items,
          offers: offers.offers,
          supermarkets: offers.supermarkets,
          favoriteSupermarketIDs: offers.favoriteSupermarketIDs,
          confirmedOfferIDs: confirmed,
        },
      }),
    [core, list, offers, confirmed],
  );

  async function act(work: () => Promise<void>, findAgain = false) {
    try {
      await work();
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
    await reloadList(findAgain);
  }

  function add() {
    const item = core.shoppingNewItem({ text: newItem }).item;
    if (!item || !list) return;
    const typed = newItem;
    setNewItem("");
    void act(async () => {
      try {
        await addItem(supabase, userID, list.list.id, item, "manual", new Date());
      } catch (error) {
        // Back in the field to try again, unless something new was typed meanwhile.
        setNewItem((current) => (current === "" ? typed : current));
        throw error;
      }
    });
  }

  /** Ticked at once, as on iOS; the list is read again once the server has it. */
  function toggle(item: Item) {
    setList((shown) => shown && { ...shown, items: shown.items.map((row) => (row.id === item.id ? { ...row, isChecked: !item.isChecked } : row)) });
    void act(() => toggleItem(supabase, userID, item, new Date()));
  }

  /** What this week's menu needs (ShoppingViewModel.fillFromMenu). */
  function fillFromMenu() {
    if (!list || filling.current) return;
    filling.current = true;
    void act(async () => {
      const ingredients = await loadRecipeIngredients(supabase, menu.entries.map((entry) => entry.recipeID));
      const change = core.shoppingRefill({
        shopping: { today: today(), items: list.items, offers: [], supermarkets: [], favoriteSupermarketIDs: [], confirmedOfferIDs: [] },
        menu,
        ingredients,
      });
      await applyRefill(supabase, userID, list.list.id, change, new Date());
    }).finally(() => {
      filling.current = false;
    });
  }

  async function invite() {
    if (!list) return;
    setSharingProblem(undefined);
    try {
      setInviteCode(await createInvite(supabase, list.list.id));
    } catch (error) {
      setSharingProblem(error instanceof Error ? error.message : "error.server");
    }
  }

  /** Joins with a code; the list of the code shows from then on. A problem shows in the sheet where the code was typed. */
  async function join(code: string, name: string): Promise<boolean> {
    setJoinProblem(undefined);
    try {
      // Limited first, as on the iPhone: a name that is cut away entirely takes the default.
      const typed = limitedText(name.trim(), 40);
      const joined = await joinList(supabase, code, typed === "" ? t("shopping.member.default") : typed);
      rememberList(userID, joined);
      await reloadList(true);
      return true;
    } catch (error) {
      setJoinProblem(error instanceof Error ? error.message : "error.server");
      return false;
    }
  }

  function leave() {
    setConfirmingLeave(false);
    if (!list) return;
    void act(async () => {
      try {
        await leaveList(supabase, list.list.id, userID);
        rememberList(userID);
      } catch (error) {
        setSharingProblem(error instanceof Error ? error.message : "error.server");
      }
    }, true);
  }

  const rows = list && offers && { ...list, ...offers };
  if (!rows || !overview) {
    return (
      <div className="tab-page pushed" data-page="shopping">
        <NavBar title={t("shopping.title")} back={t("menu.title")} onBack={onBack} large />
        <div className="loading tab-loading" aria-busy="true">
          <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
        </div>
        {failed && (
          // Without the list there is nothing to show: the message offers to read it and the shops again (UNFORGET
          // S48). OK only closes it, so a failure that lasts leaves the way back free.
          <Alert
            title={t(failed)}
            cancelLabel={t("common.ok")}
            onClose={() => setFailed(undefined)}
            actions={[
              {
                label: t("common.connection.retry"),
                onSelect: () => {
                  setFailed(undefined);
                  void reloadList(true);
                  void reloadOffers();
                },
              },
            ]}
          />
        )}
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
                <ItemRow item={item} onToggle={() => toggle(item)} />
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
      {joining && (
        <JoinSheet
          problem={joinProblem}
          onJoin={join}
          onClose={() => {
            setJoining(false);
            setJoinProblem(undefined);
          }}
        />
      )}
      {choosingShops && (
        <SupermarketPicker
          rows={rows}
          onChange={(supermarketID, favorite) =>
            void setFavoriteSupermarket(supabase, userID, supermarketID, favorite, new Date()).then(reloadOffers, (error: unknown) =>
              setFailed(error instanceof Error ? error.message : "error.server"),
            )
          }
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
      data-id={item.id}
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

/** A code from someone else, and the name the other members will see (JoinListSheet); what went wrong shows below them. */
function JoinSheet({
  problem,
  onJoin,
  onClose,
}: {
  problem?: string;
  onJoin: (code: string, name: string) => Promise<boolean>;
  onClose: () => void;
}) {
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
      <ListSection footer={problem ? t(problem === "error.network" ? "common.connection.body" : problem) : t("shopping.join.footer")}>
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
  rows: OfferRows;
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
