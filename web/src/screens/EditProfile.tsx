import { ChevronsUpDown } from "lucide-react";
import { type ReactNode, useRef, useState } from "react";
import type { Activity, BodyFields, FitlingCore, Goal, ProfileRules, Sex, Targets } from "../core/fitlingCore";
import type { Body, Profile } from "../data/profileStore";
import { outOfRange } from "../data/profileStore";
import { isIsoDay, today } from "../day";
import { decimal, parseInteger, parseNumber } from "../format";
import { t } from "../i18n";
import { activityKeys, goalKeys } from "../profileTexts";
import { useDialogFocus } from "../ui/dialogFocus";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";
import { usesMetric } from "../units";

/** A form as a sheet over the app, with Cancel and Save in its bar (a sheet with a NavigationStack on iOS). */
function FormSheet({
  title,
  canSave = true,
  onSave,
  onCancel,
  children,
}: {
  title: string;
  canSave?: boolean;
  onSave: () => void;
  onCancel: () => void;
  children: ReactNode;
}) {
  const sheet = useRef<HTMLDivElement>(null);
  useDialogFocus(sheet, onCancel);
  return (
    <div ref={sheet} className="sheet" role="dialog" aria-modal="true" aria-label={title} tabIndex={-1}>
      <NavBar
        title={title}
        leading={
          <button type="button" className="nav-back nav-action" onClick={onCancel}>
            {t("common.cancel")}
          </button>
        }
        trailing={
          <button type="button" className="nav-back nav-action nav-confirm" disabled={!canSave} onClick={onSave}>
            {t("profile.save")}
          </button>
        }
      />
      <List>{children}</List>
    </div>
  );
}

/** A Picker in a Form: the label, the chosen value on the right, the choices when tapped. */
function PickerRow<Value extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: Value;
  options: [Value, string][];
  onChange: (value: Value) => void;
}) {
  return (
    <ListRow>
      <label className="labeled picker-row">
        <span>{label}</span>
        <span className="picker-value">
          <select className="picker" value={value} onChange={(event) => onChange(event.target.value as Value)}>
            {options.map(([option, title]) => (
              <option key={option} value={option}>
                {title}
              </option>
            ))}
          </select>
          <ChevronsUpDown className="picker-chevrons" aria-hidden="true" size={14} strokeWidth={2.4} />
        </span>
      </label>
    </ListRow>
  );
}

function NumberRow({ label, value, unit, testID, onChange }: { label: string; value: string; unit: string; testID: string; onChange: (text: string) => void }) {
  return (
    <ListRow>
      <span className="number-row">
        <input
          className="text-field"
          inputMode="decimal"
          placeholder={label}
          aria-label={label}
          data-testid={testID}
          value={value}
          onChange={(event) => onChange(event.target.value)}
        />
        {unit && <span className="secondary">{unit}</span>}
      </span>
    </ListRow>
  );
}

const sexes: Sex[] = ["male", "female", "other"];

/** A stored number as the field shows it, as TextField(value:format: .number): "180,3" in Dutch. */
function shown(value: number | undefined): string {
  return value === undefined ? "" : decimal(value, 3);
}

/** Editing the profile (EditProfileView): the numbers the plan is built from, checked by FitlingCore. */
export function EditProfile({ core, profile, onSave, onCancel }: { core: FitlingCore; profile: Profile; onSave: (body: Body) => void; onCancel: () => void }) {
  const metric = usesMetric();
  const day = today();
  const stored = core.bodyInput({ usesMetric: metric, stored: { heightCm: profile.body.heightCm, weightKg: profile.body.weightKg } }).fields;
  const [birthDay, setBirthDay] = useState(profile.body.birthDay);
  const [sex, setSex] = useState<Sex>(profile.body.sex);
  const [texts, setTexts] = useState<Record<keyof BodyFields, string>>({
    centimetres: shown(stored.centimetres),
    feet: shown(stored.feet),
    inches: shown(stored.inches),
    weight: shown(stored.weight),
  });
  const [activity, setActivity] = useState<Activity>(profile.body.activityLevel);
  const [goal, setGoal] = useState<Goal>(profile.body.goal);

  // With the stored values, so unchanged fields keep them exactly (180 cm is not 5 ft 10.9 in back).
  const input = core.bodyInput({
    usesMetric: metric,
    stored: { heightCm: profile.body.heightCm, weightKg: profile.body.weightKg },
    fields: { centimetres: parseNumber(texts.centimetres), feet: parseNumber(texts.feet), inches: parseNumber(texts.inches), weight: parseNumber(texts.weight) },
  });
  // Nothing while a value is missing or outside what the database accepts.
  const edited: Body | undefined =
    input.isValid && input.heightCm !== undefined && input.weightKg !== undefined && isIsoDay(birthDay) && core.birthDay({ birthDay, today: day }).isValid
      ? { birthDay, sex, heightCm: input.heightCm, weightKg: input.weightKg, activityLevel: activity, goal }
      : undefined;
  const text = (field: keyof BodyFields) => (value: string) => setTexts({ ...texts, [field]: value });

  return (
    <FormSheet title={t("profile.edit")} canSave={edited !== undefined} onSave={() => edited && onSave(edited)} onCancel={onCancel}>
      <ListSection>
        <ListRow>
          <label className="labeled picker-row">
            <span>{t("onboarding.birthDate.label")}</span>
            <input
              className="picker"
              type="date"
              data-testid="input.birthDate"
              min="1900-01-01"
              max={day}
              value={birthDay}
              onChange={(event) => setBirthDay(event.target.value)}
            />
          </label>
        </ListRow>
        <PickerRow label={t("onboarding.sex.title")} value={sex} options={sexes.map((value) => [value, t(`onboarding.sex.${value}`)])} onChange={setSex} />
      </ListSection>
      <ListSection>
        {metric ? (
          <NumberRow label={t("onboarding.height.field")} value={texts.centimetres} unit="cm" testID="input.height" onChange={text("centimetres")} />
        ) : (
          <>
            <NumberRow label={t("onboarding.height.feet")} value={texts.feet} unit="ft" testID="input.feet" onChange={text("feet")} />
            <NumberRow label={t("onboarding.height.inches")} value={texts.inches} unit="in" testID="input.inches" onChange={text("inches")} />
          </>
        )}
        <NumberRow label={t("onboarding.weight.field")} value={texts.weight} unit={metric ? "kg" : "lb"} testID="input.weight" onChange={text("weight")} />
      </ListSection>
      <ListSection footer={edited ? undefined : <span className="message">{t("profile.profileInvalid")}</span>}>
        <PickerRow
          label={t("onboarding.activity.title")}
          value={activity}
          options={(Object.keys(activityKeys) as Activity[]).map((value) => [value, t(activityKeys[value])])}
          onChange={setActivity}
        />
        <PickerRow
          label={t("onboarding.goal.title")}
          value={goal}
          options={(Object.keys(goalKeys) as Goal[]).map((value) => [value, t(goalKeys[value])])}
          onChange={setGoal}
        />
      </ListSection>
    </FormSheet>
  );
}

const targetFields: [keyof Targets, string][] = [
  ["kcal", "profile.targets.kcal"],
  ["proteinG", "profile.targets.protein"],
  ["carbsG", "profile.targets.carbs"],
  ["fatG", "profile.targets.fat"],
];

/** Setting the targets by hand (EditTargetsView); a value the database would refuse is pointed out, not saved. */
export function EditTargets({
  targets,
  limits,
  onSave,
  onRecalculate,
  onCancel,
}: {
  targets: Targets;
  limits: ProfileRules["targetLimits"];
  onSave: (targets: Targets) => void;
  onRecalculate: () => void;
  onCancel: () => void;
}) {
  const [texts, setTexts] = useState<Record<keyof Targets, string>>({
    // Grouped as the number fields on iOS show them: "2.760".
    kcal: decimal(targets.kcal, 0),
    proteinG: decimal(targets.proteinG, 0),
    carbsG: decimal(targets.carbsG, 0),
    fatG: decimal(targets.fatG, 0),
  });
  const [showsRangeError, setShowsRangeError] = useState(false);

  function save() {
    const values = Object.fromEntries(targetFields.map(([key]) => [key, parseInteger(texts[key])])) as Record<keyof Targets, number | undefined>;
    if (targetFields.some(([key]) => values[key] === undefined)) return setShowsRangeError(true);
    const typed = values as Targets;
    if (outOfRange(typed, limits)) return setShowsRangeError(true);
    onSave(typed);
  }

  return (
    <FormSheet title={t("profile.editTargets")} onSave={save} onCancel={onCancel}>
      <ListSection footer={showsRangeError ? <span className="message">{t("profile.targets.outOfRange")}</span> : undefined}>
        {targetFields.map(([key, label]) => (
          <ListRow key={key}>
            <input
              className="text-field"
              inputMode="numeric"
              placeholder={t(label)}
              aria-label={t(label)}
              data-testid={`input.target.${key}`}
              value={texts[key]}
              onChange={(event) => setTexts({ ...texts, [key]: event.target.value })}
            />
          </ListRow>
        ))}
      </ListSection>
      <ListSection>
        <ListRow onClick={onRecalculate}>{t("profile.recalculate.confirm")}</ListRow>
      </ListSection>
    </FormSheet>
  );
}
