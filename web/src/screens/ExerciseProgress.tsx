import { type ComponentProps, useMemo, useRef, useState } from "react";
import type { FitlingCore, TrainingInput } from "../core/fitlingCore";
import { supabase } from "../data/supabase";
import { saveStep, type TrainingRows } from "../data/training";
import { t } from "../i18n";
import { adviceText, weight } from "../training/texts";
import { kilogramsPerPound, usesPounds } from "../units";
import { Alert } from "../ui/Alert";
import { useDialogFocus } from "../ui/dialogFocus";
import { ExerciseAnimation, useAnimation } from "../ui/ExerciseAnimation";
import { LineChart } from "../ui/LineChart";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";
import { Stepper } from "../ui/Stepper";
import { ExerciseRow } from "./ExercisePicker";

/** Exercises with logged working sets, to open their progress (ExerciseProgressList on iOS). */
export function ExerciseProgressList({
  core,
  input,
  equipment,
  onBack,
  onOpen,
}: {
  core: FitlingCore;
  input: TrainingInput;
  equipment: TrainingRows["equipment"];
  onBack: () => void;
  onOpen: (exerciseID: string) => void;
}) {
  const exercises = useMemo(() => core.trainingExercises({ training: input }).filter((exercise) => exercise.done), [core, input]);
  return (
    <div className="tab-page pushed" data-page="exerciseProgressList">
      <NavBar title={t("training.progress.exercises")} back={t("training.title")} onBack={onBack} large />
      <List>
        {exercises.length === 0 ? (
          <ListSection footer={t("training.progress.empty")} />
        ) : (
          <ListSection>
            {exercises.map((exercise) => (
              <ListRow key={exercise.id} onClick={() => onOpen(exercise.id)}>
                <span data-testid={`progress.exercise.${exercise.id}`}>
                  <ExerciseRow name={exercise.name} muscles={exercise.primaryMuscles} equipment={equipment[exercise.id]} />
                </span>
              </ListRow>
            ))}
          </ListSection>
        )}
      </List>
    </div>
  );
}

type ExerciseProgressProps = ComponentProps<typeof KnownExercise>;

/**
 * One exercise over time (ExerciseProgressView on iOS). Gone while it is open (removed from the catalogue, then read
 * back), only the way back is left, on a pushed screen and in a sheet alike (bug-echo of UNFORGET S42).
 */
export function ExerciseProgress(props: ExerciseProgressProps) {
  if (props.input.exercises.some((exercise) => exercise.id === props.exerciseID)) return <KnownExercise {...props} />;
  return (
    <div className="tab-page pushed" data-page="exerciseProgress">
      <NavBar title="" back={t("training.title")} onBack={props.onBack} />
    </div>
  );
}

/**
 * The animation, the estimated one-rep max per workout, the records, the advice for next time with the user's own
 * weight step, and how it is done.
 */
function KnownExercise({
  core,
  userID,
  input,
  rows,
  exerciseID,
  onBack,
  onChanged,
}: {
  core: FitlingCore;
  userID: string;
  input: TrainingInput;
  rows: TrainingRows;
  exerciseID: string;
  onBack: () => void;
  onChanged: () => Promise<void>;
}) {
  const pounds = usesPounds();
  const progress = useMemo(() => core.exerciseProgress({ training: input, exerciseID }), [core, input, exerciseID]);
  const exercise = input.exercises.find((candidate) => candidate.id === exerciseID);
  const name = exercise ? core.localizedText({ values: exercise.name, languages: input.languages }).text : "";
  const instructions = core.localizedText({ values: rows.instructions[exerciseID] ?? {}, languages: input.languages }).text;
  const animation = useAnimation(exerciseID);
  const [step, setStep] = useState(progress.stepKg);
  const [failed, setFailed] = useState<string>();
  const toUnit = (kg: number) => (pounds ? kg / kilogramsPerPound : kg);
  // Steps are stored one after the other (as Partner.change): quick taps leave one setting, with the last step.
  const saving = useRef<Promise<void>>(Promise.resolve());

  function changeStep(value: number) {
    setStep(value);
    saving.current = saving.current
      .then(() => saveStep(supabase, userID, exerciseID, value, new Date()))
      .then(onChanged)
      .catch((error: unknown) => setFailed(error instanceof Error ? error.message : "error.server"));
  }

  return (
    <div className="tab-page pushed" data-page="exerciseProgress">
      <NavBar title={name} back={t("training.title")} onBack={onBack} large />
      <List>
        {animation && (
          <ListSection footer={t("training.animation.legend")}>
            <div className="list-row animation-row">
              <ExerciseAnimation exerciseID={exerciseID} manifest={animation} />
            </div>
          </ListSection>
        )}
        <ListSection header={t("training.chart.oneRepMax")} footer={t("training.chart.footer")}>
          <div className="list-row chart-row">
            {progress.points.length >= 2 ? (
              <LineChart
                points={progress.points.map((point) => ({ day: point.day, value: toUnit(point.kg) }))}
                unit={pounds ? "lb" : "kg"}
                label={t("training.chart.oneRepMax")}
              />
            ) : (
              <span className="footnote secondary">{t("training.chart.needsTwo")}</span>
            )}
          </div>
        </ListSection>
        <ListSection header={t("training.records.title")}>
          {progress.heaviestKg !== undefined && (
            <div className="list-row labeled-row">
              <span>{t("training.records.heaviest")}</span>
              <span className="value">{weight(progress.heaviestKg, pounds)}</span>
            </div>
          )}
          {progress.bestOneRepMaxKg !== undefined && (
            <div className="list-row labeled-row">
              <span>{t("training.records.oneRepMax")}</span>
              <span className="value">{weight(progress.bestOneRepMaxKg, pounds)}</span>
            </div>
          )}
          <div className="list-row labeled-row">
            <span>{t("training.records.workouts")}</span>
            <span className="value" data-testid="progress.workouts">
              {progress.workouts}
            </span>
          </div>
        </ListSection>
        <ListSection header={t("training.step.title")} footer={t("training.step.footer")}>
          <div className="list-row" data-testid="progress.advice">
            {adviceText(progress.advice, pounds)}
          </div>
          <ListRow>
            <Stepper label={t("training.step.label %@", weight(step, pounds))} value={step} min={0.25} max={25} step={0.25} onChange={changeStep} testID="progress.step" />
          </ListRow>
        </ListSection>
        {instructions !== "" && (
          <ListSection header={t("training.instructions")}>
            <div className="list-row instructions">{instructions}</div>
          </ListSection>
        )}
      </List>
      {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
    </div>
  );
}

/** An exercise opened from a sheet or a workout, over it, with its own focus and Escape (a NavigationLink there). */
export function ExerciseSheet({ label, ...props }: ExerciseProgressProps & { label: string }) {
  const sheet = useRef<HTMLDivElement>(null);
  useDialogFocus(sheet, props.onBack);
  return (
    <div ref={sheet} className="sheet" role="dialog" aria-modal="true" aria-label={label} tabIndex={-1}>
      <ExerciseProgress {...props} />
    </div>
  );
}
