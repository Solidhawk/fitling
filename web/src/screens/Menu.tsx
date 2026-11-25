import { BookOpen, Check, CircleCheck, Pin, PinOff, RefreshCw, SlidersHorizontal, TriangleAlert } from "lucide-react";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { FitlingCore, Goal, MenuChange, MenuInput, MenuIssue, MenuOverview, MenuPreferences, Targets } from "../core/fitlingCore";
import { useCore } from "../core/useCore";
import {
  applyMenuChange,
  deleteRecipe,
  loadMenu,
  logMeal,
  type MenuRows,
  removeEntry,
  savePreferences,
  setPinned,
  swapRecipe,
} from "../data/menu";
import { loadProfile, loadTargetPeriods, type Profile } from "../data/profileStore";
import { supabase } from "../data/supabase";
import { today } from "../day";
import { useHistoryStack } from "../historyStack";
import { t } from "../i18n";
import { dayHeading, entryDetail, issueText, type MenuOptions, rememberedMenuOptions, rememberMenuOptions } from "../menu/texts";
import { ActionSheet } from "../ui/ActionSheet";
import { Alert } from "../ui/Alert";
import { PrimaryButton } from "../ui/Buttons";
import { List, ListRow, ListSection } from "../ui/List";
import { SwipeRow } from "../ui/SwipeRow";
import { MenuGenerator, MenuPreferencesSheet } from "./MenuGenerator";
import { OwnRecipeForm, RecipeDetail, RecipeList, RecipePicker, RecipeThumbnail } from "./Recipes";

type Route = { kind: "recipes" } | { kind: "recipe"; id: string };
type Entry = MenuOverview["days"][number]["entries"][number];

interface Loaded {
  rows: MenuRows;
  profile: Profile;
  periods: Awaited<ReturnType<typeof loadTargetPeriods>>;
}

/** A random UInt64 as text: another seed gives another menu from the same recipes. */
function seed(): string {
  return crypto.getRandomValues(new BigUint64Array(1))[0].toString();
}

/**
 * The menu tab (MenuTabView.swift): per day the planned meals, to pin, swap or log with one tap; a new menu, other
 * meals for one day, the preferences and the recipes. The shopping list comes with phase 6. Recipes are pushed
 * screens (back and swiping back go through the browser's history).
 */
export function Menu({ userID }: { userID: string }) {
  const core = useCore();
  const [loaded, setLoaded] = useState<Loaded>();
  const [failed, setFailed] = useState<string>();
  const [issues, setIssues] = useState<MenuIssue[]>([]);
  const [path, setPath] = useState<Route[]>([]);
  const [generating, setGenerating] = useState(false);
  const [editingPreferences, setEditingPreferences] = useState(false);
  const [creating, setCreating] = useState(false);
  const [swapping, setSwapping] = useState<string>();
  const [menuFor, setMenuFor] = useState<Entry>();
  const back = useHistoryStack(path.length, (depth) => setPath((shown) => shown.slice(0, depth)));
  const push = (route: Route) => setPath((shown) => [...shown, route]);
  // One change of the menu at a time: a double tap makes one menu, not two on top of each other.
  const busy = useRef(false);
  // Preferences are stored one after the other, so a quick second change never lands before the first.
  const storing = useRef<Promise<void>>(Promise.resolve());

  const reload = useCallback(async () => {
    try {
      const [rows, profile, periods] = await Promise.all([loadMenu(supabase, today()), loadProfile(supabase, userID), loadTargetPeriods(supabase)]);
      setLoaded({ rows, profile, periods });
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
  }, [userID]);

  useEffect(() => {
    void reload();
    const again = () => document.visibilityState === "visible" && void reload();
    document.addEventListener("visibilitychange", again);
    return () => document.removeEventListener("visibilitychange", again);
  }, [reload]);

  useEffect(() => window.scrollTo(0, 0), [path.length]);

  const input = useMemo<MenuInput | undefined>(
    () => loaded && { userID, today: today(), languages: [...navigator.languages], ...withoutSteps(loaded.rows) },
    [loaded, userID],
  );
  const overview = useMemo(() => (core && input ? core.menuOverview({ menu: input }) : undefined), [core, input]);

  async function act(work: () => Promise<void>) {
    try {
      await work();
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
    await reload();
  }

  /** The targets a menu plans for: the day's own target, or what the formulas give for `goal` (MenuStore.targets). */
  function targets(core: FitlingCore, goal?: Goal): Targets {
    const { profile, periods } = loaded!;
    if (goal) return core.dailyPlan({ ...profile.body, goal, today: today() }).targets;
    return core.targetsOnDay({ day: today(), fallback: profile.targets, periods });
  }

  /** What FitlingCore decided, stored; its issues stay in view until the next change (MenuViewModel.generate). */
  function change(decide: () => MenuChange) {
    if (busy.current) return;
    busy.current = true;
    const decided = decide();
    setIssues(decided.issues);
    void act(() => applyMenuChange(supabase, userID, decided, new Date())).finally(() => {
      busy.current = false;
    });
  }

  function make(options: MenuOptions) {
    setGenerating(false);
    if (!core || !input) return;
    rememberMenuOptions(options);
    change(() => core.menuGenerate({ menu: input, days: options.days, seed: seed(), targets: targets(core, options.goal) }));
  }

  /** New meals for one day, for the goal of the last menu (MenuViewModel.renew). */
  function renew(day: string) {
    if (!core || !input) return;
    change(() => core.menuRenew({ menu: input, day, seed: seed(), targets: targets(core, rememberedMenuOptions().goal) }));
  }

  function log(entry: Entry) {
    if (!core || !input || busy.current) return;
    const meal = core.menuLoggedMeal({ menu: input, entryID: entry.id }).meal;
    if (!meal) return;
    busy.current = true;
    void act(async () => {
      await logMeal(supabase, userID, entry.id, meal, new Date());
    }).finally(() => {
      busy.current = false;
    });
  }

  function pin(entry: Entry) {
    void act(() => setPinned(supabase, entry.id, !entry.isPinned, new Date()));
  }

  /** An action of the long-press menu: the menu closes first, as a context menu does. */
  function closingMenu(action: () => void) {
    return () => {
      setMenuFor(undefined);
      action();
    };
  }

  function changePreferences(preferences: MenuPreferences) {
    if (!loaded) return;
    // Shown and used at once; stored in the background, as each change is saved on iOS.
    setLoaded({ ...loaded, rows: { ...loaded.rows, settings: preferences } });
    storing.current = storing.current
      .then(() => savePreferences(supabase, userID, preferences, new Date()))
      .catch((error: unknown) => setFailed(error instanceof Error ? error.message : "error.server"));
  }

  const route = path.at(-1);
  let screen;
  if (!core || !loaded || !input || !overview) {
    screen = (
      <div className="tab-page" data-page="menu">
        <h1 className="large-title">{t("menu.title")}</h1>
        <div className="loading tab-loading" aria-busy="true">
          <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
        </div>
      </div>
    );
  } else if (route?.kind === "recipe") {
    const recipe = overview.recipes.find((candidate) => candidate.id === route.id);
    screen = recipe ? (
      <RecipeDetail key={recipe.id} rows={loaded.rows} recipe={recipe} back={path.length > 1 ? t("menu.recipes") : t("menu.title")} onBack={back} />
    ) : (
      // A recipe removed on another device, or a meal whose recipe is gone.
      <div className="tab-page pushed" data-page="recipe" />
    );
  } else if (route?.kind === "recipes") {
    screen = (
      <RecipeList
        core={core}
        recipes={overview.recipes}
        onBack={back}
        onOpen={(id) => push({ kind: "recipe", id })}
        onCreate={() => setCreating(true)}
        onDelete={(id) => void act(() => deleteRecipe(supabase, id, new Date()))}
      />
    );
  } else {
    screen = (
      <MenuList
        overview={overview}
        issues={issues}
        onPreferences={() => setEditingPreferences(true)}
        onGenerate={() => setGenerating(true)}
        onRenew={renew}
        onOpen={(id) => push({ kind: "recipe", id })}
        onRecipes={() => push({ kind: "recipes" })}
        onLog={log}
        onSwap={(entry) => setSwapping(entry.id)}
        onPin={pin}
        onMenu={setMenuFor}
      />
    );
  }

  return (
    <>
      {screen}
      {generating && core && loaded && (
        <MenuGenerator
          initial={rememberedMenuOptions()}
          targets={(goal) => targets(core, goal)}
          preferences={loaded.rows.settings}
          onPreferences={changePreferences}
          onMake={make}
          onCancel={() => setGenerating(false)}
        />
      )}
      {editingPreferences && loaded && (
        <MenuPreferencesSheet preferences={loaded.rows.settings} onChange={changePreferences} onDone={() => setEditingPreferences(false)} />
      )}
      {swapping && core && input && (
        <RecipePicker
          core={core}
          recipes={core.menuRecipesFor({ menu: input, entryID: swapping })}
          onCancel={() => setSwapping(undefined)}
          onPick={(recipeID) => {
            const entryID = swapping;
            setSwapping(undefined);
            void act(() => swapRecipe(supabase, entryID, recipeID, new Date()));
          }}
        />
      )}
      {menuFor && (
        <ActionSheet
          title={menuFor.title}
          onCancel={() => setMenuFor(undefined)}
          actions={[
            { label: t("menu.log"), onSelect: closingMenu(() => log(menuFor)) },
            { label: t("menu.swap"), onSelect: closingMenu(() => setSwapping(menuFor.id)) },
            { label: t(menuFor.isPinned ? "menu.unpin" : "menu.pin"), onSelect: closingMenu(() => pin(menuFor)) },
            { label: t("menu.remove"), destructive: true, onSelect: closingMenu(() => void act(() => removeEntry(supabase, menuFor.id, new Date()))) },
          ]}
        />
      )}
      {creating && core && (
        <OwnRecipeForm
          core={core}
          userID={userID}
          onCancel={() => setCreating(false)}
          onSaved={() => {
            setCreating(false);
            void reload();
          }}
          onFailed={setFailed}
        />
      )}
      {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
    </>
  );
}

/** The rows FitlingCore reads; the steps are for the recipe screen only. */
function withoutSteps(rows: MenuRows): Omit<MenuRows, "steps"> {
  const { steps: _, ...rest } = rows;
  return rest;
}

/**
 * A day's date and the button for other meals on that day only. The date keeps one line: when the button's text does
 * not fit beside it, only its icon is shown, and its name stays for screen readers (ViewThatFits on iOS).
 */
function DayHeader({ day, onRenew }: { day: string; onRenew: () => void }) {
  const header = useRef<HTMLDivElement>(null);
  const [compact, setCompact] = useState(false);

  useLayoutEffect(() => {
    const element = header.current;
    if (!element) return;
    const fit = () => {
      element.dataset.compact = "false";
      const overflows = element.scrollWidth > element.clientWidth + 1;
      element.dataset.compact = String(overflows);
      setCompact(overflows);
    };
    fit();
    const observer = new ResizeObserver(fit);
    observer.observe(element);
    return () => observer.disconnect();
  }, [day]);

  return (
    <div ref={header} className="menu-day-header" data-compact={compact}>
      <h2 className="menu-day-title">{dayHeading(day)}</h2>
      <button type="button" className="inline-action menu-renew" aria-label={t("menu.day.renew")} data-testid={`menu.day.renew.${day}`} onClick={onRenew}>
        <RefreshCw aria-hidden="true" size={18} strokeWidth={2.4} />
        <span className="menu-renew-label" aria-hidden="true">
          {t("menu.day.renew")}
        </span>
      </button>
    </div>
  );
}

function EntryRow({
  entry,
  own,
  onOpen,
  onLog,
  onSwap,
  onPin,
  onMenu,
}: {
  entry: Entry;
  /** The recipe is the user's own: no photo. */
  own: boolean;
  onOpen: () => void;
  onLog: () => void;
  onSwap: () => void;
  onPin: () => void;
  onMenu: () => void;
}) {
  const open = !entry.logged;
  const icon = { "aria-hidden": true, size: 20, strokeWidth: 2.2 } as const;
  return (
    <SwipeRow
      bare
      leading={open ? [{ label: t("menu.log"), icon: <Check {...icon} />, tone: "sprout", onSelect: onLog, testID: `menu.log.${entry.id}` }] : []}
      trailing={
        open
          ? [
              { label: t("menu.swap"), icon: <RefreshCw {...icon} />, tone: "ink", onSelect: onSwap, testID: `menu.swap.${entry.id}` },
              {
                label: t(entry.isPinned ? "menu.unpin" : "menu.pin"),
                icon: entry.isPinned ? <PinOff {...icon} /> : <Pin {...icon} />,
                tone: "pebble",
                onSelect: onPin,
                testID: `menu.pin.${entry.id}`,
              },
            ]
          : []
      }
      onMenu={open ? onMenu : undefined}
    >
      <button type="button" className="list-row list-row-button menu-entry" data-testid={`menu.entry.${entry.id}`} onClick={onOpen}>
        <RecipeThumbnail id={entry.recipeID} own={own} title={entry.title} />
        <span className="row-stack menu-entry-text">
          <span className="footnote secondary menu-entry-slot">{t(`meal.${entry.slot}`)}</span>
          <span>{entry.title}</span>
          <span className="footnote secondary tabular">{entryDetail(entry.servings, entry.kcal)}</span>
        </span>
        {entry.logged ? (
          <span className="menu-entry-state" data-testid={`menu.logged.${entry.id}`}>
            <CircleCheck aria-hidden="true" size={22} strokeWidth={2.2} fill="currentColor" stroke="var(--card)" />
            <span className="visually-hidden">{t("menu.logged")}</span>
          </span>
        ) : (
          entry.isPinned && (
            <span className="menu-entry-state" data-testid={`menu.pinned.${entry.id}`}>
              <Pin aria-hidden="true" size={20} strokeWidth={2.2} fill="currentColor" />
              <span className="visually-hidden">{t("menu.pinned")}</span>
            </span>
          )
        )}
      </button>
    </SwipeRow>
  );
}

function MenuList({
  overview,
  issues,
  onPreferences,
  onGenerate,
  onRenew,
  onOpen,
  onRecipes,
  onLog,
  onSwap,
  onPin,
  onMenu,
}: {
  overview: MenuOverview;
  issues: MenuIssue[];
  onPreferences: () => void;
  onGenerate: () => void;
  onRenew: (day: string) => void;
  onOpen: (recipeID: string) => void;
  onRecipes: () => void;
  onLog: (entry: Entry) => void;
  onSwap: (entry: Entry) => void;
  onPin: (entry: Entry) => void;
  onMenu: (entry: Entry) => void;
}) {
  const empty = overview.days.length === 0;
  const own = new Set(overview.recipes.filter((recipe) => recipe.own).map((recipe) => recipe.id));
  return (
    <div className="tab-page" data-page="menu">
      <div className="toolbar toolbar-split">
        <button type="button" className="nav-back nav-action icon-button" aria-label={t("menu.preferences")} data-testid="menu.preferences" onClick={onPreferences}>
          <SlidersHorizontal aria-hidden="true" size={24} strokeWidth={2} />
        </button>
        {!empty && (
          <button type="button" className="nav-back nav-action" data-testid="menu.generate" onClick={onGenerate}>
            {t("menu.regenerate")}
          </button>
        )}
      </div>
      <h1 className="large-title">{t("menu.title")}</h1>
      <List>
        {empty && (
          <section className="list-section menu-empty">
            <p className="menu-empty-text">{t("menu.empty")}</p>
            <PrimaryButton onClick={onGenerate} data-testid="menu.generate.first">
              {t("menu.generate")}
            </PrimaryButton>
          </section>
        )}
        {issues.length > 0 && (
          <ListSection header={t("menu.issues.title")}>
            {issues.map((issue, index) => (
              <div key={index} className="list-row coach-row" data-testid="menu.issue">
                <TriangleAlert aria-hidden="true" size={22} strokeWidth={2} />
                <span>{issueText(issue)}</span>
              </div>
            ))}
          </ListSection>
        )}
        {overview.days.map((group) => (
          <ListSection key={group.day} lead={<DayHeader day={group.day} onRenew={() => onRenew(group.day)} />}>
            {group.entries.map((entry) => (
              <EntryRow
                key={entry.id}
                entry={entry}
                own={own.has(entry.recipeID)}
                onOpen={() => onOpen(entry.recipeID)}
                onLog={() => onLog(entry)}
                onSwap={() => onSwap(entry)}
                onPin={() => onPin(entry)}
                onMenu={() => onMenu(entry)}
              />
            ))}
          </ListSection>
        ))}
        <ListSection>
          <ListRow onClick={onRecipes} chevron>
            <span className="icon-label" data-testid="menu.recipes">
              <BookOpen aria-hidden="true" size={22} strokeWidth={2} />
              <span>{t("menu.recipes")}</span>
            </span>
          </ListRow>
        </ListSection>
      </List>
    </div>
  );
}
