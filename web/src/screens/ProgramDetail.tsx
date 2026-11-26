import { CircleEllipsis, Play, Plus } from "lucide-react";
import { useRef, useState } from "react";
import type { FitlingCore, TrainingInput } from "../core/fitlingCore";
import { supabase } from "../data/supabase";
import { addItem, copyProgram, deleteProgram, removeItem, renameProgram, type TrainingRows, typingLanguage } from "../data/training";
import { language, t } from "../i18n";
import { ActionSheet } from "../ui/ActionSheet";
import { Alert } from "../ui/Alert";
import { List, ListRow, ListSection } from "../ui/List";
import { Menu } from "../ui/Menu";
import { NavBar } from "../ui/NavBar";
import { SwipeRow } from "../ui/SwipeRow";
import { ExercisePicker } from "./ExercisePicker";

/**
 * One programme with its days and their exercises (ProgramDetailView.swift). A ready-made programme can be started
 * or copied; the user's own can be renamed, removed and changed, except a composed day: that is the record of one
 * workout, and another one is composed instead.
 */
export function ProgramDetail({
  core,
  userID,
  input,
  rows,
  programID,
  onBack,
  onChanged,
  onStart,
  onOpenExercise,
  onOpenCopy,
}: {
  core: FitlingCore;
  userID: string;
  input: TrainingInput;
  rows: TrainingRows;
  programID: string;
  onBack: () => void;
  onChanged: () => Promise<void>;
  onStart: (dayID: string) => void;
  onOpenExercise: (exerciseID: string) => void;
  onOpenCopy: (programID: string) => void;
}) {
  const program = core.programDetail({ training: input, programID });
  const [addingTo, setAddingTo] = useState<string>();
  const [renaming, setRenaming] = useState<string>();
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [failed, setFailed] = useState<string>();

  async function act(work: () => Promise<unknown>) {
    try {
      await work();
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
    await onChanged();
  }

  // One copy at a time: a double tap makes one.
  const copying = useRef(false);

  /** A composed day carries its date, or ten times "Bovenlichaam" could not be told apart. */
  function title(day: (typeof program.days)[number]): string {
    if (!day.composed) return day.name;
    return `${day.name} · ${new Intl.DateTimeFormat(language(), { day: "numeric", month: "short" }).format(new Date(day.updatedAt * 1000))}`;
  }

  const trailing = program.own ? (
    <Menu
      label={t("training.program.options")}
      icon={<CircleEllipsis aria-hidden="true" size={24} strokeWidth={2} />}
      testID="program.options"
      items={[
        { label: t("training.program.rename"), onSelect: () => setRenaming(program.name) },
        { label: t("training.program.delete"), onSelect: () => setConfirmingDelete(true), destructive: true },
      ]}
    />
  ) : (
    <button
      type="button"
      className="nav-back nav-action"
      onClick={() => {
        if (copying.current) return;
        copying.current = true;
        let copy: string | undefined;
        // Opened once it is read back, so FitlingCore knows it.
        void act(async () => {
          copy = await copyProgram(supabase, userID, rows, programID, { name: t("training.program.copyName %@", program.name), language: typingLanguage() }, new Date());
        })
          .then(() => copy && onOpenCopy(copy))
          .finally(() => {
            copying.current = false;
          });
      }}
    >
      {t("training.program.copy")}
    </button>
  );

  return (
    <div className="tab-page pushed" data-page="program">
      <NavBar title={program.name} back={t("training.title")} onBack={onBack} trailing={trailing} large />
      <List>
        {program.days.map((day) => (
          <ListSection key={day.id} header={<span className="day-header">{title(day)}</span>}>
            {day.items.map((item) => {
              const row = (
                <ListRow onClick={() => onOpenExercise(item.exerciseID)} chevron>
                  <span className="row-stack" data-testid={`program.exercise.${item.exerciseID}`}>
                    <span>{item.exerciseName}</span>
                    <span className="footnote secondary">{t("training.item.detail %lld %lld %lld %lld", item.targetSets, item.repMin, item.repMax, item.restSeconds)}</span>
                  </span>
                </ListRow>
              );
              return day.canChange ? (
                <SwipeRow key={item.id} deleteLabel={t("day.delete")} onDelete={() => void act(() => removeItem(supabase, item.id, new Date()))}>
                  {row}
                </SwipeRow>
              ) : (
                <div key={item.id}>{row}</div>
              );
            })}
            {day.canChange && (
              <ListRow onClick={() => setAddingTo(day.id)}>
                <span className="inline-action" data-testid={`program.add.${day.id}`}>
                  <Plus aria-hidden="true" size={18} strokeWidth={2.4} />
                  <span>{t("training.program.addExercise")}</span>
                </span>
              </ListRow>
            )}
            <ListRow onClick={() => onStart(day.id)} disabled={day.items.length === 0}>
              <span className="inline-action strong" data-testid={`training.start.${day.id}`}>
                <Play aria-hidden="true" size={18} strokeWidth={2.4} fill="currentColor" />
                <span>{t("training.program.start")}</span>
              </span>
            </ListRow>
          </ListSection>
        ))}
      </List>
      {addingTo && (
        <ExercisePicker
          core={core}
          input={input}
          equipment={rows.equipment}
          onCancel={() => setAddingTo(undefined)}
          onPick={(exercise, sets, repMin, repMax, rest) => {
            const day = program.days.find((candidate) => candidate.id === addingTo);
            setAddingTo(undefined);
            const position = Math.max(-1, ...rows.items.filter((item) => item.programDayID === addingTo).map((item) => item.position)) + 1;
            void act(() =>
              addItem(supabase, userID, { dayID: day?.id ?? addingTo, exerciseID: exercise, position, sets, repMin, repMax, restSeconds: rest }, new Date()),
            );
          }}
        />
      )}
      {renaming !== undefined && (
        <Alert
          title={t("training.program.rename")}
          onClose={() => setRenaming(undefined)}
          field={
            <input
              className="text-field alert-input"
              aria-label={t("training.program.name")}
              placeholder={t("training.program.name")}
              value={renaming}
              onChange={(event) => setRenaming(event.target.value)}
            />
          }
          actions={[
            {
              label: t("common.save"),
              disabled: renaming.trim() === "",
              onSelect: () => {
                const name = renaming.trim();
                setRenaming(undefined);
                if (name !== "") void act(() => renameProgram(supabase, programID, name, typingLanguage(), new Date()));
              },
            },
          ]}
        />
      )}
      {confirmingDelete && (
        <ActionSheet
          title={t("training.program.delete.title")}
          message={t("training.program.delete.body")}
          actions={[
            {
              label: t("training.program.delete"),
              destructive: true,
              onSelect: () => {
                setConfirmingDelete(false);
                void act(() => deleteProgram(supabase, programID, new Date())).then(onBack);
              },
            },
          ]}
          onCancel={() => setConfirmingDelete(false)}
        />
      )}
      {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
    </div>
  );
}
