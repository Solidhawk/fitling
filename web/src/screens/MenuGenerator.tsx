import { useState } from "react";
import type { Goal, MenuPreferences, Targets } from "../core/fitlingCore";
import { mealSlots } from "../data/menu";
import { t } from "../i18n";
import { menuDays, type MenuOptions } from "../menu/texts";
import { goalKeys } from "../profileTexts";
import { PrimaryButton } from "../ui/Buttons";
import { FormSheet } from "../ui/FormSheet";
import { ListRow, ListSection } from "../ui/List";
import { PickerRow } from "../ui/PickerRow";
import { Stepper } from "../ui/Stepper";

const tags = ["meat", "fish", "dairy", "egg", "gluten", "nuts", "soy", "sesame"];
const cookLimits = ["", "15", "30", "45", "60"];
const goals: Goal[] = ["lose", "build_muscle", "maintain", "recomp"];

function Toggle({ label, checked, onChange, testID }: { label: string; checked: boolean; onChange: (checked: boolean) => void; testID: string }) {
  return (
    <ListRow>
      <label className="toggle-row">
        <span>{label}</span>
        <input type="checkbox" role="switch" className="switch" data-testid={testID} checked={checked} onChange={(event) => onChange(event.target.checked)} />
      </label>
    </ListRow>
  );
}

/**
 * The menu preferences as list sections: which meals, what to leave out, cooking time and meal prep
 * (MenuPreferenceSections). Shared by the preferences sheet and the menu generator; every change is saved at once.
 */
export function MenuPreferenceSections({ preferences, onChange }: { preferences: MenuPreferences; onChange: (preferences: MenuPreferences) => void }) {
  return (
    <>
      <ListSection header={t("menu.prefs.meals")}>
        {mealSlots.map((slot) => (
          <Toggle
            key={slot}
            label={t(`meal.${slot}`)}
            testID={`menu.prefs.slot.${slot}`}
            checked={preferences.mealSlots.includes(slot)}
            onChange={(on) => {
              // At least one meal stays in the menu.
              if (!on && preferences.mealSlots.length <= 1) return;
              const chosen = on ? [...preferences.mealSlots, slot] : preferences.mealSlots.filter((other) => other !== slot);
              onChange({ ...preferences, mealSlots: mealSlots.filter((other) => chosen.includes(other)) });
            }}
          />
        ))}
      </ListSection>
      <ListSection header={t("menu.prefs.without")}>
        {tags.map((tag) => (
          <Toggle
            key={tag}
            label={t(`menu.tag.${tag}`)}
            testID={`menu.prefs.tag.${tag}`}
            checked={preferences.excludedTags.includes(tag)}
            onChange={(on) => onChange({ ...preferences, excludedTags: tags.filter((other) => (other === tag ? on : preferences.excludedTags.includes(other))) })}
          />
        ))}
      </ListSection>
      <ListSection footer={t("menu.prefs.mealPrep.footer")}>
        <PickerRow
          label={t("menu.prefs.cookTime")}
          value={preferences.maxCookMinutes === undefined ? "" : String(preferences.maxCookMinutes)}
          options={cookLimits.map((limit) => [limit, limit === "" ? t("menu.prefs.noLimit") : t("menu.prefs.minutes %lld", Number(limit))])}
          onChange={(limit: string) => onChange({ ...preferences, maxCookMinutes: limit === "" ? undefined : Number(limit) })}
        />
        <Toggle
          label={t("menu.prefs.mealPrep")}
          testID="menu.prefs.mealPrep"
          checked={preferences.mealPrep}
          onChange={(mealPrep) => onChange({ ...preferences, mealPrep })}
        />
      </ListSection>
    </>
  );
}

/** Which meals the menu plans, what to leave out, how long cooking may take and meal prep (MenuPreferencesView). */
export function MenuPreferencesSheet({
  preferences,
  onChange,
  onDone,
}: {
  preferences: MenuPreferences;
  onChange: (preferences: MenuPreferences) => void;
  onDone: () => void;
}) {
  return (
    <FormSheet title={t("menu.preferences")} saveLabel={t("common.ok")} onSave={onDone} onCancel={onDone}>
      <MenuPreferenceSections preferences={preferences} onChange={onChange} />
    </FormSheet>
  );
}

/**
 * Making a menu: how many days from today, for which goal, which meals and what to leave out; then one tap
 * (MenuGeneratorView). It opens with the choices of the last menu.
 */
export function MenuGenerator({
  initial,
  targets,
  preferences,
  onPreferences,
  onMake,
  onCancel,
}: {
  initial: MenuOptions;
  /** The kcal a menu for that goal plans for; undefined is the daily target. */
  targets: (goal?: Goal) => Targets;
  preferences: MenuPreferences;
  onPreferences: (preferences: MenuPreferences) => void;
  onMake: (options: MenuOptions) => void;
  onCancel: () => void;
}) {
  const [days, setDays] = useState(initial.days);
  const [goal, setGoal] = useState(initial.goal);

  const goalRow = (choice: Goal | undefined) => (
    <button
      key={choice ?? "daily"}
      type="button"
      role="radio"
      aria-checked={goal === choice}
      className="list-row list-row-button choice"
      data-testid={`menu.generator.goal.${choice ?? "daily"}`}
      onClick={() => setGoal(choice)}
    >
      <span className="choice-text">
        <span>{t(choice ? goalKeys[choice] : "menu.generator.goal.daily")}</span>
        <span className="choice-detail tabular">{t("menu.generator.goal.kcal %lld", targets(choice).kcal)}</span>
      </span>
      {goal === choice && (
        <svg className="checkmark" viewBox="0 0 14 12" aria-hidden="true">
          <path d="M1 6.5l4 4L13 1" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
    </button>
  );

  return (
    <FormSheet title={t("menu.generator.title")} onSave={onCancel} onCancel={onCancel}>
      <ListSection header={t("menu.generator.days.title")} footer={t("menu.generator.days.footer")}>
        <ListRow>
          <Stepper
            label={t("menu.generator.days %lld", days)}
            value={days}
            min={1}
            max={menuDays}
            onChange={setDays}
            testID="menu.generator.days"
          />
        </ListRow>
      </ListSection>
      <ListSection header={t("menu.generator.goal")}>
        <div role="radiogroup" aria-label={t("menu.generator.goal")}>
          {goalRow(undefined)}
          {goals.map(goalRow)}
        </div>
      </ListSection>
      <MenuPreferenceSections preferences={preferences} onChange={onPreferences} />
      <div className="bottom-bar">
        <PrimaryButton onClick={() => onMake(goal ? { days, goal } : { days })} data-testid="menu.generator.make">
          {t("menu.generator.make %lld", days)}
        </PrimaryButton>
      </div>
    </FormSheet>
  );
}
