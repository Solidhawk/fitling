import { useMemo, useState } from "react";
import type { FitlingCore, TrainingInput, WorkoutPlan } from "../core/fitlingCore";
import type { TrainingRows } from "../data/training";
import { language, t } from "../i18n";
import { rememberedMinutes, rememberMinutes } from "../training/minutes";
import { focusTitle, listed, muscleName } from "../training/texts";
import { PrimaryButton } from "../ui/Buttons";
import { FormSheet } from "../ui/FormSheet";
import { ListRow, ListSection } from "../ui/List";
import { PickerRow } from "../ui/PickerRow";
import { ExerciseSheet } from "./ExerciseProgress";

export interface ComposeChoice {
  focus: string;
  plan: WorkoutPlan;
}

/** "borst, rug en schouders", for inside a sentence ([MuscleGroup].inSentence on iOS). */
function inSentence(muscles: string[]): string {
  return listed(muscles.map((muscle) => muscleName(muscle).toLocaleLowerCase(language())));
}

/** "Borst, rug, schouders, biceps en triceps": only the first keeps its capital (TrainingFocus.muscleList). */
function muscleList(muscles: string[]): string {
  const list = inSentence(muscles);
  return list.charAt(0).toLocaleUpperCase(language()) + list.slice(1);
}

/**
 * Compose a workout (ComposeWorkoutView.swift): how long and what to train, the exercises FitlingCore picks for it
 * from every exercise and the history, and start. The time is remembered on this device.
 */
export function ComposeWorkout({
  core,
  userID,
  input,
  rows,
  focus: initial,
  onStart,
  onCancel,
  onChanged,
}: {
  core: FitlingCore;
  userID: string;
  input: TrainingInput;
  rows: TrainingRows;
  focus: string;
  onStart: (choice: ComposeChoice) => void;
  onCancel: () => void;
  onChanged: () => Promise<void>;
}) {
  const choices = useMemo(() => core.trainingChoices(), [core]);
  const [minutes, setMinutes] = useState(() => rememberedMinutes(choices));
  const [focus, setFocus] = useState(initial);
  const plan = useMemo(() => core.composePlan({ training: input, focus, minutes }), [core, input, focus, minutes]);
  // A planned exercise opens its animation and progress over the sheet, as a NavigationLink on iOS.
  const [opened, setOpened] = useState<string>();
  return (
    <FormSheet title={t("training.compose.title")} onSave={() => undefined} onCancel={onCancel}>
      <div className="sheet-bottom-space">
        <ListSection
          header={t("training.compose.duration")}
          footer={
            plan.exercises.length > 0 && (
              <span className="row-stack">
                <span>{t("training.compose.estimate %lld", plan.roundedMinutes)}</span>
                {plan.minutes <= choices.shortWorkoutMinutes && <span>{t("training.compose.short")}</span>}
                {plan.leftOut.length > 0 && <span>{t("training.compose.leftOut %@", inSentence(plan.leftOut))}</span>}
                {plan.leavesTimeOver && <span>{t("training.compose.timeOver")}</span>}
              </span>
            )
          }
        >
          <PickerRow
            label={t("training.compose.time")}
            value={String(minutes)}
            options={choices.durations.map((value) => [String(value), t("training.compose.minutes %lld", value)])}
            onChange={(value: string) => {
              setMinutes(Number(value));
              rememberMinutes(Number(value));
            }}
          />
        </ListSection>
        <ListSection header={t("training.compose.focus")}>
          <div role="radiogroup" aria-label={t("training.compose.focus")}>
            {choices.focuses.map((option) => (
              <button
                key={option.id}
                type="button"
                role="radio"
                aria-checked={focus === option.id}
                className="list-row list-row-button choice"
                data-testid={`training.compose.focus.${option.id}`}
                onClick={() => setFocus(option.id)}
              >
                <span className="choice-text">
                  <span>{focusTitle(option.id)}</span>
                  <span className="choice-detail">{muscleList(option.muscles)}</span>
                </span>
                {focus === option.id && (
                  <svg className="checkmark" viewBox="0 0 14 12" aria-hidden="true">
                    <path d="M1 6.5l4 4L13 1" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                )}
              </button>
            ))}
          </div>
        </ListSection>
        <ListSection header={t("training.compose.exercises")} footer={t("training.compose.footer")}>
          {plan.exercises.length === 0 && <ListRow>{t("training.compose.none")}</ListRow>}
          {plan.exercises.map((planned) => (
            <ListRow key={planned.exerciseID} onClick={() => setOpened(planned.exerciseID)} chevron>
              <span className="planned-row" data-testid={`training.compose.exercise.${planned.exerciseID}`}>
                <span>{planned.name}</span>
                <span className="planned-sets">{t("training.compose.sets %lld %lld %lld", planned.sets, planned.repMin, planned.repMax)}</span>
              </span>
            </ListRow>
          ))}
        </ListSection>
      </div>
      {opened && (
        <ExerciseSheet
          label={t("training.compose.title")}
          core={core}
          userID={userID}
          input={input}
          rows={rows}
          exerciseID={opened}
          onBack={() => setOpened(undefined)}
          onChanged={onChanged}
        />
      )}
      <div className="bottom-bar">
        <PrimaryButton disabled={plan.exercises.length === 0} onClick={() => onStart({ focus, plan })} data-testid="training.compose.start">
          {t("training.compose.start")}
        </PrimaryButton>
      </div>
    </FormSheet>
  );
}
