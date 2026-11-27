import { ChevronLeft, ChevronRight, Droplet, Plus } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import type { DayTotals, FitlingCore, PartnerSnapshot, Targets } from "../core/fitlingCore";
import { useCore } from "../core/useCore";
import { type Partner, partnerWeek } from "../data/creature";
import { addWater, deleteEntry, entriesOn, type FoodEntry, type Meal, meals, waterOn } from "../data/diary";
import { loadProfile, loadTargetPeriods } from "../data/profileStore";
import { notSaved, takeRefused, toldEvent } from "../data/offline";
import { loadReminderSettings, planReminders } from "../data/push";
import { supabase } from "../data/supabase";
import { addDays, today } from "../day";
import { decimal, kcal, millilitres } from "../format";
import { language, t } from "../i18n";
import { Alert } from "../ui/Alert";
import { DayCard } from "../ui/DayCard";
import { List, ListRow, ListSection } from "../ui/List";
import { SwipeRow } from "../ui/SwipeRow";
import { LogFood } from "./LogFood";

interface Shown {
  entries: FoodEntry[];
  water: number;
  totals: DayTotals;
  targets: Targets;
  partner?: Partner;
  snapshot?: PartnerSnapshot;
  /** The partner could not be read or brought up to date this time: the card keeps the one it showed. */
  partnerFailed?: boolean;
}

/** Folds finished days into the partner and returns it, once for Vandaag and the partner tab together (Home). */
export type Advance = (core: FitlingCore) => Promise<Partner | undefined>;

async function load(core: FitlingCore, userID: string, day: string, advance: Advance): Promise<Shown> {
  const now = today();
  // The partner is the card's alone: when folding the days into it or reading its week fails, the day shows without it,
  // and the next reload tries again.
  const partnerPart = Promise.all([advance(core), partnerWeek(supabase, now)]).catch(() => undefined);
  const [entries, water, profile, periods, partnerAndWeek] = await Promise.all([
    entriesOn(supabase, day),
    waterOn(supabase, day),
    loadProfile(supabase, userID),
    loadTargetPeriods(supabase),
    partnerPart,
  ]);
  const [partner, week] = partnerAndWeek ?? [];
  // The target that applied on that day; earlier days keep theirs.
  const targets = core.targetsOnDay({ day, fallback: profile.targets, periods });
  const totals = core.dayTotals({ entries });
  // The partner as it is today, also when an earlier day is shown, as the iPhone shows it; its reminders are planned
  // from the same days, as HomeView does when the app opens or comes back.
  const days = partner && week ? { creature: partner.state, ...week, periods, fallback: profile.targets, today: now } : undefined;
  const snapshot = partner && days ? core.partnerSnapshot(days) : undefined;
  if (partner && days) void planReminders(supabase, core, { settings: loadReminderSettings(), name: partner.name, days }).catch(() => undefined);
  return { entries, water, totals, targets, partner, snapshot, partnerFailed: partnerAndWeek === undefined };
}

/** The title: "Vandaag", or the weekday with its date. */
function title(day: string): string {
  if (day === today()) return t("day.today");
  const [year, month, date] = day.split("-").map(Number);
  return new Intl.DateTimeFormat(language(), { weekday: "long", day: "numeric", month: "long" }).format(new Date(year, month - 1, date));
}

function amount(entry: FoodEntry): string {
  const quantity = decimal(entry.quantity, 1);
  if (entry.quantityUnit === "serving") return t("portion.servings %@", quantity);
  return `${quantity} ${entry.quantityUnit === "ml" ? "ml" : "g"}`;
}

/**
 * One day: what was eaten per meal, the totals against the target that applied that day, and water (DayView.swift).
 * Read again when the tab comes back, so what another device logged shows up.
 */
export function Day({ userID, advance }: { userID: string; advance: Advance }) {
  const core = useCore();
  const [day, setDay] = useState(today());
  const [shown, setShown] = useState<Shown>();
  const [logging, setLogging] = useState<Meal>();
  const [failed, setFailed] = useState<string>();
  const [unsaved, setUnsaved] = useState(false);
  const request = useRef(0);
  // Looking at today: the screen moves on with the date, so what is logged the next morning lands on that day. A day the
  // user went back to stays (DayViewModel.dateChanged).
  const followsToday = useRef(true);

  // An answer that a newer request overtook is dropped: tapping back twice quickly shows the second day, not
  // whichever answer came in last.
  const reload = useCallback(async () => {
    if (!core) return;
    const mine = ++request.current;
    try {
      const next = await load(core, userID, day, advance);
      // The partner is today's on every day shown: a card that showed it keeps it through a failed read.
      if (mine === request.current) {
        setShown((before) => (next.partnerFailed && before?.partner ? { ...next, partner: before.partner, snapshot: before.snapshot } : next));
      }
      // What waited in this browser and was sent later: a write the server turned down is told once, and one that
      // keeps waiting although the server answers gets a line.
      if (takeRefused() > 0) setFailed("offline.refused");
      setUnsaved(notSaved());
    } catch (error) {
      if (mine === request.current) setFailed(error instanceof Error ? error.message : "error.server");
    }
  }, [core, userID, day, advance]);

  function show(next: string) {
    followsToday.current = next >= today();
    setShown(undefined);
    setDay(next);
  }

  /**
   * The date moved on while the user looked at today: the screen follows, and a log sheet that was open closes, so
   * nothing lands on a day the screen no longer shows. True when it moved.
   */
  function moveOn(): boolean {
    const now = today();
    if (!followsToday.current || day === now) return false;
    setLogging(undefined);
    show(now);
    return true;
  }

  useEffect(() => {
    // Every minute, and when the page or the window comes back: a timer stops while a laptop sleeps, and a window that
    // stayed in front gets no visibilitychange.
    const timer = setInterval(moveOn, 60_000);
    const back = () => document.visibilityState === "visible" && moveOn();
    document.addEventListener("visibilitychange", back);
    window.addEventListener("focus", moveOn);
    return () => {
      clearInterval(timer);
      document.removeEventListener("visibilitychange", back);
      window.removeEventListener("focus", moveOn);
    };
  }, [day]);

  useEffect(() => {
    void reload();
    const again = () => document.visibilityState === "visible" && void reload();
    // Sending what waited turned up something to tell (offline.ts): shown at once, not at the next visit.
    const told = () => void reload();
    document.addEventListener("visibilitychange", again);
    window.addEventListener(toldEvent, told);
    return () => {
      document.removeEventListener("visibilitychange", again);
      window.removeEventListener(toldEvent, told);
    };
  }, [reload]);

  async function change(work: () => Promise<void>) {
    try {
      await work();
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
    await reload();
  }

  // The future has nothing to log yet.
  const isToday = day >= today();
  return (
    <div className="tab-page" data-page="day">
      <div className="toolbar">
        <button type="button" className="nav-back nav-action icon-button" aria-label={t("day.previous")} onClick={() => show(addDays(day, -1))}>
          <ChevronLeft aria-hidden="true" size={24} strokeWidth={2.2} />
        </button>
        <button
          type="button"
          className="nav-back nav-action icon-button"
          aria-label={t("day.next")}
          disabled={isToday}
          onClick={() => show(addDays(day, 1) > today() ? today() : addDays(day, 1))}
        >
          <ChevronRight aria-hidden="true" size={24} strokeWidth={2.2} />
        </button>
      </div>
      <h1 className="large-title">{title(day)}</h1>
      {!shown || !core ? (
        <div className="loading tab-loading" aria-busy="true">
          <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
        </div>
      ) : (
        <List>
          <ListSection
            lead={<DayCard totals={shown.totals} targets={shown.targets} partner={shown.partner} snapshot={shown.snapshot} />}
            footer={
              shown.totals.unknownProtein + shown.totals.unknownCarbs + shown.totals.unknownFat > 0 ? (
                <span className="unknown-macros">
                  {shown.totals.unknownProtein > 0 && <span>{t("day.unknown.protein %lld", shown.totals.unknownProtein)}</span>}
                  {shown.totals.unknownCarbs > 0 && <span>{t("day.unknown.carbs %lld", shown.totals.unknownCarbs)}</span>}
                  {shown.totals.unknownFat > 0 && <span>{t("day.unknown.fat %lld", shown.totals.unknownFat)}</span>}
                </span>
              ) : undefined
            }
          />
          <ListSection header={t("water.title")}>
            <ListRow>
              <span className="labeled">
                <span className="water-amount" data-testid="water.amount">
                  {millilitres(shown.water)}
                </span>
                <button
                  type="button"
                  className="inline-action"
                  data-testid="water.add"
                  // Past midnight before any check came: the first tap moves on and writes nothing on yesterday.
                  onClick={() => moveOn() || void change(() => addWater(supabase, userID, day, new Date()))}
                >
                  <Droplet aria-hidden="true" size={18} strokeWidth={2.2} fill="currentColor" />
                  <span>{t("water.add")}</span>
                </button>
              </span>
            </ListRow>
          </ListSection>
          {meals.map((meal) => {
            const entries = shown.entries.filter((entry) => entry.meal === meal);
            return (
              <ListSection
                key={meal}
                header={
                  <span className="meal-header">
                    <span>{t(`meal.${meal}`)}</span>
                    <span data-testid={`day.kcal.${meal}`}>{kcal(entries.reduce((total, entry) => total + entry.kcal, 0))}</span>
                  </span>
                }
              >
                {entries.map((entry) => (
                  <SwipeRow
                    key={entry.id}
                    deleteLabel={t("day.delete")}
                    onDelete={() => void change(() => deleteEntry(supabase, entry.id, new Date()))}
                  >
                    <span className="entry-row" data-testid="day.entry">
                      <span className="entry-text">
                        <span>{entry.name}</span>
                        <span className="footnote secondary">{amount(entry)}</span>
                      </span>
                      <span className="value">{kcal(entry.kcal)}</span>
                    </span>
                  </SwipeRow>
                ))}
                <ListRow onClick={() => moveOn() || setLogging(meal)}>
                  <span className="inline-action" data-testid={`day.add.${meal}`}>
                    <Plus aria-hidden="true" size={18} strokeWidth={2.4} />
                    <span>{t("day.add")}</span>
                  </span>
                </ListRow>
              </ListSection>
            );
          })}
          {unsaved && <ListSection footer={<span data-testid="day.unsaved">{t("account.unsynced.title")}</span>} />}
        </List>
      )}
      {logging && core && (
        <LogFood
          core={core}
          userID={userID}
          meal={logging}
          day={day}
          onClose={() => {
            setLogging(undefined);
            void reload();
          }}
        />
      )}
      {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
    </div>
  );
}
