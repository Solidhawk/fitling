import { ChevronLeft, ChevronRight, Droplet, Plus } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import type { DayTotals, FitlingCore, PartnerSnapshot, Targets } from "../core/fitlingCore";
import { useCore } from "../core/useCore";
import { type Partner, partnerWeek } from "../data/creature";
import { addWater, deleteEntry, entriesOn, type FoodEntry, type Meal, meals, waterOn } from "../data/diary";
import { loadProfile, loadTargetPeriods } from "../data/profileStore";
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
}

/** Folds finished days into the partner and returns it, once for Vandaag and the partner tab together (Home). */
export type Advance = (core: FitlingCore) => Promise<Partner | undefined>;

async function load(core: FitlingCore, userID: string, day: string, advance: Advance): Promise<Shown> {
  const now = today();
  const [entries, water, profile, periods, partner, week] = await Promise.all([
    entriesOn(supabase, day),
    waterOn(supabase, day),
    loadProfile(supabase, userID),
    loadTargetPeriods(supabase),
    advance(core),
    partnerWeek(supabase, now),
  ]);
  // The target that applied on that day; earlier days keep theirs.
  const targets = core.targetsOnDay({ day, fallback: profile.targets, periods });
  const totals = core.dayTotals({ entries });
  // The partner as it is today, also when an earlier day is shown, as the iPhone shows it; its reminders are planned
  // from the same days, as HomeView does when the app opens or comes back.
  const days = partner ? { creature: partner.state, ...week, periods, fallback: profile.targets, today: now } : undefined;
  const snapshot = partner && days ? core.partnerSnapshot(days) : undefined;
  if (partner && days) void planReminders(supabase, core, { settings: loadReminderSettings(), name: partner.name, days }).catch(() => undefined);
  return { entries, water, totals, targets, partner, snapshot };
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
  const request = useRef(0);

  // An answer that a newer request overtook is dropped: tapping back twice quickly shows the second day, not
  // whichever answer came in last.
  const reload = useCallback(async () => {
    if (!core) return;
    const mine = ++request.current;
    try {
      const next = await load(core, userID, day, advance);
      if (mine === request.current) setShown(next);
    } catch (error) {
      if (mine === request.current) setFailed(error instanceof Error ? error.message : "error.server");
    }
  }, [core, userID, day, advance]);

  function show(next: string) {
    setShown(undefined);
    setDay(next);
  }

  useEffect(() => {
    void reload();
    const again = () => document.visibilityState === "visible" && void reload();
    document.addEventListener("visibilitychange", again);
    return () => document.removeEventListener("visibilitychange", again);
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
                  onClick={() => void change(() => addWater(supabase, userID, day, new Date()))}
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
                <ListRow onClick={() => setLogging(meal)}>
                  <span className="inline-action" data-testid={`day.add.${meal}`}>
                    <Plus aria-hidden="true" size={18} strokeWidth={2.4} />
                    <span>{t("day.add")}</span>
                  </span>
                </ListRow>
              </ListSection>
            );
          })}
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
