import { Activity, BicepsFlexed, Dumbbell, PersonStanding, Search, StretchHorizontal, Weight } from "lucide-react";
import { useMemo, useState } from "react";
import type { FitlingCore, TrainingInput } from "../core/fitlingCore";
import type { TrainingRows } from "../data/training";
import { t } from "../i18n";
import { listed, muscleName } from "../training/texts";
import { FormSheet } from "../ui/FormSheet";
import { ListRow, ListSection } from "../ui/List";
import { Stepper } from "../ui/Stepper";

/** The equipment of an exercise as an icon (EquipmentKind.symbol on iOS, in Lucide's shapes). */
export function EquipmentIcon({ equipment }: { equipment?: string }) {
  const props = { "aria-hidden": true, size: 22, strokeWidth: 2 } as const;
  switch (equipment) {
    case "barbell":
    case "dumbbell":
      return <Dumbbell {...props} />;
    case "machine":
    case "cable":
      return <BicepsFlexed {...props} />;
    case "kettlebell":
      return <Weight {...props} />;
    case "band":
      return <StretchHorizontal {...props} />;
    case "bodyweight":
      return <PersonStanding {...props} />;
    default:
      return <Activity {...props} />;
  }
}

/** An exercise with its main muscle groups, as a list row (ExerciseRow on iOS). */
export function ExerciseRow({ name, muscles, equipment }: { name: string; muscles: string[]; equipment?: string }) {
  return (
    <span className="icon-label">
      <EquipmentIcon equipment={equipment} />
      <span className="row-stack">
        <span>{name}</span>
        <span className="footnote secondary">{listed(muscles.map(muscleName))}</span>
      </span>
    </span>
  );
}

/**
 * Picks an exercise and how it is trained: sets, rep range and rest (ExercisePicker on iOS). An isolation exercise
 * starts at 10–15 reps and a minute of rest.
 */
export function ExercisePicker({
  core,
  input,
  equipment,
  onPick,
  onCancel,
}: {
  core: FitlingCore;
  input: TrainingInput;
  equipment: TrainingRows["equipment"];
  onPick: (exerciseID: string, sets: number, repMin: number, repMax: number, rest: number) => void;
  onCancel: () => void;
}) {
  const [query, setQuery] = useState("");
  const [chosen, setChosen] = useState<{ id: string; name: string }>();
  const [sets, setSets] = useState(3);
  const [repMin, setRepMin] = useState(8);
  const [repMax, setRepMax] = useState(12);
  const [rest, setRest] = useState(120);
  const all = useMemo(() => core.trainingExercises({ training: input }), [core, input]);
  const keys = useMemo(() => all.map((exercise) => core.searchKey({ text: exercise.name }).key), [core, all]);
  const term = core.searchKey({ text: query }).key;
  const matches = term === "" ? all : all.filter((_, index) => keys[index].includes(term));

  function choose(exercise: (typeof all)[number]) {
    setChosen(exercise);
    if (exercise.kind === "isolation") {
      setRepMin(10);
      setRepMax(15);
      setRest(60);
    }
  }

  return (
    <FormSheet
      title={t("training.picker.title")}
      saveLabel={chosen ? t("common.save") : undefined}
      onSave={() => chosen && onPick(chosen.id, sets, repMin, Math.max(repMin, repMax), rest)}
      onCancel={onCancel}
    >
      {chosen ? (
        <ListSection>
          <ListRow>
            <span className="row-headline heavy">{chosen.name}</span>
          </ListRow>
          <ListRow>
            <Stepper label={t("training.picker.sets %lld", sets)} value={sets} min={1} max={10} onChange={setSets} testID="picker.sets" />
          </ListRow>
          <ListRow>
            <Stepper label={t("training.picker.repMin %lld", repMin)} value={repMin} min={1} max={repMax} onChange={setRepMin} />
          </ListRow>
          <ListRow>
            <Stepper label={t("training.picker.repMax %lld", repMax)} value={repMax} min={repMin} max={100} onChange={setRepMax} />
          </ListRow>
          <ListRow>
            <Stepper label={t("training.picker.rest %lld", rest)} value={rest} min={0} max={900} step={15} onChange={setRest} />
          </ListRow>
        </ListSection>
      ) : (
        <>
          <div className="search-bar">
            <Search aria-hidden="true" size={18} strokeWidth={2.2} />
            <input
              className="search-field"
              type="search"
              aria-label={t("training.picker.search")}
              placeholder={t("training.picker.search")}
              data-testid="picker.search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
            />
          </div>
          <ListSection>
            {matches.map((exercise) => (
              <ListRow key={exercise.id} onClick={() => choose(exercise)}>
                <span data-testid={`picker.exercise.${exercise.id}`}>
                  <ExerciseRow name={exercise.name} muscles={exercise.primaryMuscles} equipment={equipment[exercise.id]} />
                </span>
              </ListRow>
            ))}
          </ListSection>
        </>
      )}
    </FormSheet>
  );
}
