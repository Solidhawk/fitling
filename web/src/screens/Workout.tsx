import { Ellipsis, Info, Plus } from "lucide-react";
import { useRef, useState } from "react";
import type { FitlingCore, WorkoutEntry } from "../core/fitlingCore";
import { supabase } from "../data/supabase";
import { discardWorkout, finishWorkout, logSet, removeSet, type TrainingRows } from "../data/training";
import { parseNumber } from "../format";
import { language, t } from "../i18n";
import { trainingInput } from "../training/input";
import { adviceText, recordText, weight } from "../training/texts";
import { usesPounds } from "../units";
import { ActionSheet } from "../ui/ActionSheet";
import { Alert } from "../ui/Alert";
import { PrimaryButton } from "../ui/Buttons";
import { useDialogFocus } from "../ui/dialogFocus";
import { List, ListRow, ListSection } from "../ui/List";
import { Menu } from "../ui/Menu";
import { NavBar } from "../ui/NavBar";
import { RestTimer } from "../ui/RestTimer";
import { SwipeRow } from "../ui/SwipeRow";
import { ExercisePicker } from "./ExercisePicker";
import { ExerciseProgress } from "./ExerciseProgress";

/** What the user is about to log for one exercise, as typed, in their own unit (WorkoutViewModel.Draft). */
interface Draft {
  weight: string;
  reps: string;
  rpe?: number;
  isWarmup: boolean;
}

const rpeChoices = Array.from({ length: 9 }, (_, index) => 6 + index / 2);

function typed(value: number | undefined): string {
  return value === undefined ? "" : new Intl.NumberFormat(language(), { maximumFractionDigits: 2, useGrouping: false }).format(value);
}

/**
 * A workout in progress (WorkoutView.swift): per exercise the advice, the sets so far and the next set to log, with a
 * rest timer after every working set. The next set is filled in from the advice when the exercise appears, and keeps
 * what the user typed after that.
 */
export function Workout({
  core,
  userID,
  rows,
  sessionID,
  onChanged,
  onClose,
}: {
  core: FitlingCore;
  userID: string;
  rows: TrainingRows;
  sessionID: string;
  onChanged: () => Promise<void>;
  onClose: () => void;
}) {
  const pounds = usesPounds();
  const sheet = useRef<HTMLDivElement>(null);
  const [added, setAdded] = useState<string[]>([]);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [restEndsAt, setRestEndsAt] = useState<number>();
  const [adding, setAdding] = useState(false);
  const [confirmingDiscard, setConfirmingDiscard] = useState(false);
  const [records, setRecords] = useState<string[]>([]);
  const [opened, setOpened] = useState<string>();
  const [failed, setFailed] = useState<string>();
  const [busy, setBusy] = useState(false);
  useDialogFocus(sheet, () => undefined);

  const input = trainingInput(userID, rows);
  const session = rows.sessions.find((candidate) => candidate.id === sessionID);
  const workout = session ? core.workout({ training: input, sessionID, added, usesPounds: pounds }) : undefined;
  const entries = workout?.entries ?? [];
  const sets = rows.sets.filter((set) => set.sessionID === sessionID).sort((a, b) => a.position - b.position);

  // An exercise that appears gets its next set filled in once (WorkoutViewModel.prefill).
  const missing = entries.filter((entry) => drafts[entry.exerciseID] === undefined);
  if (missing.length > 0) {
    setDrafts((shown) => {
      const next = { ...shown };
      for (const entry of missing) {
        next[entry.exerciseID] ??= { weight: typed(entry.draft.weight), reps: typed(entry.draft.reps), isWarmup: false };
      }
      return next;
    });
  }

  const draftOf = (entry: WorkoutEntry): Draft => drafts[entry.exerciseID] ?? { weight: "", reps: "", isWarmup: false };
  const change = (entry: WorkoutEntry, patch: Partial<Draft>) =>
    setDrafts((shown) => ({ ...shown, [entry.exerciseID]: { ...draftOf(entry), ...patch } }));

  function stored(entry: WorkoutEntry) {
    const draft = draftOf(entry);
    const reps = parseNumber(draft.reps);
    return core.loggedSet({
      weight: parseNumber(draft.weight),
      reps: reps === undefined || !Number.isInteger(reps) ? undefined : reps,
      rpe: draft.rpe,
      usesPounds: pounds,
    });
  }

  async function act(work: () => Promise<unknown>) {
    setBusy(true);
    try {
      await work();
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
    await onChanged();
    setBusy(false);
  }

  /** Stores the draft as a set; a working set starts the rest timer, and RPE is asked again for the next one. */
  function log(entry: WorkoutEntry) {
    const set = stored(entry);
    if (!set.canLog || busy) return;
    const draft = draftOf(entry);
    const position = Math.max(-1, ...sets.map((candidate) => candidate.position)) + 1;
    void act(async () => {
      await logSet(supabase, userID, { sessionID, exerciseID: entry.exerciseID, position, weightKg: set.weightKg, reps: set.reps, rpe: set.rpe, isWarmup: draft.isWarmup }, new Date());
      if (!draft.isWarmup) setRestEndsAt(Date.now() + entry.restSeconds * 1000);
      change(entry, { rpe: undefined });
    });
  }

  function finish() {
    if (!session) return;
    const found = core.workoutRecords({ training: input, sessionID, exerciseIDs: entries.map((entry) => entry.exerciseID) });
    void act(async () => {
      await finishWorkout(supabase, session, new Date());
      setRestEndsAt(undefined);
      if (found.length === 0) onClose();
      else setRecords(found.map((record) => recordText(record.name, record.record, pounds)));
    });
  }

  function discard() {
    setConfirmingDiscard(false);
    const cleanup = core.discardCleanup({ training: input, sessionID });
    void act(() => discardWorkout(supabase, sessionID, cleanup, new Date())).then(onClose);
  }

  // The long first-time advice once, at the first exercise it applies to; later ones point back to it.
  const firstNew = entries.find((entry) => entry.advice.kind === "findStartingWeight")?.exerciseID;
  const adviceFor = (entry: WorkoutEntry) =>
    entry.advice.kind === "findStartingWeight" && entry.exerciseID !== firstNew ? t("training.advice.startAgain") : adviceText(entry.advice, pounds);

  if (opened) {
    return (
      <div ref={sheet} className="sheet" role="dialog" aria-modal="true" aria-label={workout?.title ?? t("training.session.free")} tabIndex={-1}>
        <ExerciseProgress core={core} userID={userID} input={input} rows={rows} exerciseID={opened} onBack={() => setOpened(undefined)} onChanged={onChanged} />
      </div>
    );
  }

  return (
    <div ref={sheet} className="sheet workout" role="dialog" aria-modal="true" aria-label={workout?.title ?? t("training.session.free")} tabIndex={-1}>
      <NavBar
        title={workout?.title ?? t("training.session.free")}
        leading={
          <Menu
            label={t("training.workout.options")}
            icon={<Ellipsis aria-hidden="true" size={24} strokeWidth={2.2} />}
            testID="workout.options"
            items={[
              { label: t("training.workout.later"), onSelect: onClose },
              { label: t("training.workout.discard"), onSelect: () => setConfirmingDiscard(true), destructive: true },
            ]}
          />
        }
        trailing={
          <button type="button" className="nav-back nav-action nav-confirm" data-testid="workout.finish" disabled={busy} onClick={finish}>
            {t("training.workout.finish")}
          </button>
        }
      />
      <List>
        {entries.map((entry) => {
          const draft = draftOf(entry);
          const done = sets.filter((set) => set.exerciseID === entry.exerciseID);
          return (
            <ListSection
              key={entry.exerciseID}
              header={
                <span className="row-stack entry-header">
                  <span className="row-headline heavy">{entry.name}</span>
                  <span className="footnote">{t("training.workout.target %lld %lld %lld", entry.rules.targetSets, entry.rules.repMin, entry.rules.repMax)}</span>
                </span>
              }
            >
              <ListRow onClick={() => setOpened(entry.exerciseID)} chevron>
                <span className="icon-label" data-testid={`workout.exercise.${entry.exerciseID}`}>
                  <Info aria-hidden="true" size={22} strokeWidth={2} />
                  <span>{t("training.exercise.explain")}</span>
                </span>
              </ListRow>
              <div className="list-row advice-row">{adviceFor(entry)}</div>
              {done.map((set, index) => (
                <SwipeRow key={set.id} deleteLabel={t("day.delete")} onDelete={() => void act(() => removeSet(supabase, set.id, new Date()))}>
                  <span className="set-row" data-testid="workout.set">
                    <span className="set-number">{index + 1}</span>
                    <span className="set-summary">{t("training.set.summary %@ %lld", weight(set.weightKg, pounds), set.reps)}</span>
                    {set.isWarmup ? (
                      <span className="footnote secondary">{t("training.set.warmup")}</span>
                    ) : (
                      set.rpe !== undefined && (
                        <span className="footnote secondary">
                          {t("training.set.rpe %@", new Intl.NumberFormat(language(), { maximumFractionDigits: 1 }).format(set.rpe))}
                        </span>
                      )
                    )}
                  </span>
                </SwipeRow>
              ))}
              <div className="list-row draft-row">
                <div className="draft-fields">
                  <label className="number-box">
                    <span className="number-box-label">{t("training.set.weight")}</span>
                    <span className="number-box-field">
                      <input
                        inputMode="decimal"
                        aria-label={t("training.set.weight")}
                        data-testid={`workout.weight.${entry.exerciseID}`}
                        value={draft.weight}
                        onChange={(event) => change(entry, { weight: event.target.value })}
                        onKeyDown={(event) => event.key === "Enter" && log(entry)}
                      />
                      <span className="secondary">{pounds ? "lb" : "kg"}</span>
                    </span>
                  </label>
                  <label className="number-box">
                    <span className="number-box-label">{t("training.set.reps")}</span>
                    <span className="number-box-field">
                      <input
                        inputMode="numeric"
                        aria-label={t("training.set.reps")}
                        data-testid={`workout.reps.${entry.exerciseID}`}
                        value={draft.reps}
                        onChange={(event) => change(entry, { reps: event.target.value })}
                        onKeyDown={(event) => event.key === "Enter" && log(entry)}
                      />
                      <span className="secondary">{t("training.set.repsUnit")}</span>
                    </span>
                  </label>
                </div>
                <div className="draft-options">
                  <select
                    className="picker rpe-picker"
                    aria-label={t("training.set.rpeLabel")}
                    value={draft.rpe === undefined ? "" : String(draft.rpe)}
                    onChange={(event) => change(entry, { rpe: event.target.value === "" ? undefined : Number(event.target.value) })}
                  >
                    <option value="">{t("training.set.rpeNone")}</option>
                    {rpeChoices.map((value) => (
                      <option key={value} value={String(value)}>
                        {new Intl.NumberFormat(language(), { maximumFractionDigits: 1 }).format(value)}
                      </option>
                    ))}
                  </select>
                  <label className="toggle-row warmup-toggle">
                    <span>{t("training.set.warmup")}</span>
                    <input type="checkbox" role="switch" className="switch" checked={draft.isWarmup} onChange={(event) => change(entry, { isWarmup: event.target.checked })} />
                  </label>
                </div>
                <PrimaryButton disabled={!stored(entry).canLog || busy} onClick={() => log(entry)} data-testid={`workout.log.${entry.exerciseID}`}>
                  {t("training.set.log")}
                </PrimaryButton>
              </div>
            </ListSection>
          );
        })}
        <ListSection>
          <ListRow onClick={() => setAdding(true)}>
            <span className="inline-action" data-testid="workout.add">
              <Plus aria-hidden="true" size={18} strokeWidth={2.4} />
              <span>{t("training.workout.addExercise")}</span>
            </span>
          </ListRow>
        </ListSection>
      </List>
      {restEndsAt !== undefined && <RestTimer endsAt={restEndsAt} onSkip={() => setRestEndsAt(undefined)} />}
      {adding && (
        <ExercisePicker
          core={core}
          input={input}
          equipment={rows.equipment}
          onCancel={() => setAdding(false)}
          onPick={(exerciseID) => {
            setAdding(false);
            setAdded((shown) => (shown.includes(exerciseID) ? shown : [...shown, exerciseID]));
          }}
        />
      )}
      {confirmingDiscard && (
        <ActionSheet
          title={t("training.workout.discard.title")}
          actions={[{ label: t("training.workout.discard"), destructive: true, onSelect: discard }]}
          onCancel={() => setConfirmingDiscard(false)}
        />
      )}
      {records.length > 0 && (
        <Alert
          title={t("training.records.title")}
          message={records.join("\n")}
          onClose={() => {
            setRecords([]);
            onClose();
          }}
        />
      )}
      {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
    </div>
  );
}
