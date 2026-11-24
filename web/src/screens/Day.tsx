import { ChevronLeft, ChevronRight, Droplet, Plus } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import type { DayTotals, FitlingCore, PartnerSnapshot, Targets } from "../core/fitlingCore";
import { useCore } from "../core/useCore";
import { loadPartner, type Partner } from "../data/creature";
import { addWater, deleteEntry, entriesBetween, entriesOn, type FoodEntry, type Meal, meals, waterOn, workoutDaysBetween } from "../data/diary";
import { loadProfile, loadTargetPeriods } from "../data/profileStore";
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

/** The kcal of the partner's week: more than the eight days FitlingCore looks at, which it picks itself. */
const partnerDays = 14;

async function load(core: FitlingCore, userID: string, day: string): Promise<Shown> {
  const now = today();
  const [entries, water, profile, periods, partner, week, workouts] = await Promise.all([
    entriesOn(supabase, day),
    waterOn(supabase, day),
    loadProfile(supabase, userID),
    loadTargetPeriods(supabase),
    loadPartner(supabase, userID),
    entriesBetween(supabase, addDays(now, -partnerDays), now),
    workoutDaysBetween(supabase, addDays(now, -partnerDays), now),
  ]);
  // The target that applied on that day; earlier days keep theirs.
  const targets = core.targetsOnDay({ day, fallback: profile.targets, periods });
  const totals = core.dayTotals({ entries });
  // The partner as it is today, also when an earlier day is shown, as the iPhone shows it.
  const snapshot = partner
    ? core.partnerSnapshot({
        creature: partner.state,
        entries: week.map((entry) => ({ day: entry.consumedOn, kcal: entry.kcal, proteinG: entry.proteinG })),
        workoutDays: workouts,
        periods,
        fallback: profile.targets,
        today: now,
      })
    : undefined;
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
export function Day({ userID }: { userID: string }) {
  const core = useCore();
  const [day, setDay] = useState(today());
  const [shown, setShown] = useState<Shown>();
  const [logging, setLogging] = useState<Meal>();
  const [failed, setFailed] = useState<string>();

  const reload = useCallback(async () => {
    if (!core) return;
    try {
      setShown(await load(core, userID, day));
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
  }, [core, userID, day]);

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
        <button type="button" className="nav-back nav-action icon-button" aria-label={t("day.previous")} onClick={() => setDay(addDays(day, -1))}>
          <ChevronLeft aria-hidden="true" size={24} strokeWidth={2.2} />
        </button>
        <button
          type="button"
          className="nav-back nav-action icon-button"
          aria-label={t("day.next")}
          disabled={isToday}
          onClick={() => setDay(addDays(day, 1) > today() ? today() : addDays(day, 1))}
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
