import { useState } from "react";
import type { Activity, BodyFields, DailyPlanInput, Goal } from "../core/fitlingCore";
import { useCore } from "../core/useCore";
import { useHistoryStack } from "../historyStack";
import { isIsoDay, thirtyYearsBefore, today } from "../day";
import { finishOnboarding } from "../data/saveProfile";
import { supabase } from "../data/supabase";
import { parseNumber, percent } from "../format";
import { t } from "../i18n";
import { activityKeys, goalKeys, orderedWarnings, warningKeys } from "../profileTexts";
import { Alert } from "../ui/Alert";
import { PrimaryButton, SecondaryButton } from "../ui/Buttons";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";
import { TargetsCard } from "../ui/TargetsCard";
import { usesMetric } from "../units";

const steps = ["consent", "birthDate", "sex", "height", "weight", "activity", "goal", "result"] as const;
type Step = (typeof steps)[number];

const titles: Record<Step, string> = {
  consent: "consent.title",
  birthDate: "onboarding.birthDate.title",
  sex: "onboarding.sex.title",
  height: "onboarding.height.title",
  weight: "onboarding.weight.title",
  activity: "onboarding.activity.title",
  goal: "onboarding.goal.title",
  result: "onboarding.result.title",
};

/**
 * The eight onboarding steps, each pushed on the previous one (OnboardingFlowView.swift and
 * OnboardingViewModel.swift). Every check and number comes from FitlingCore.
 */
export function Onboarding({ userID, onFinished, onDeleteAccount }: { userID: string; onFinished: () => void; onDeleteAccount: () => void }) {
  const core = useCore();
  const day = today();
  const metric = usesMetric();
  const [step, setStep] = useState<Step>("consent");
  const [consent, setConsent] = useState(false);
  const [birthDay, setBirthDay] = useState(thirtyYearsBefore(day));
  const [sex, setSex] = useState<DailyPlanInput["sex"]>();
  const [texts, setTexts] = useState<Record<keyof BodyFields, string>>({ centimetres: "", feet: "", inches: "", weight: "" });
  const [activity, setActivity] = useState<Activity>();
  const [goal, setGoal] = useState<Goal>();
  const [saving, setSaving] = useState(false);
  const [saveFailed, setSaveFailed] = useState(false);

  // Each step is pushed on the one before: swiping back or the browser's back button goes one step back.
  const back = useHistoryStack(steps.indexOf(step), (depth) => setStep(steps[depth]));

  if (!core) {
    return (
      <main className="screen loading" data-screen="onboarding" aria-busy="true">
        <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
      </main>
    );
  }

  const fields: BodyFields = {
    centimetres: parseNumber(texts.centimetres),
    feet: parseNumber(texts.feet),
    inches: parseNumber(texts.inches),
    weight: parseNumber(texts.weight),
  };
  const body = core.bodyInput({ usesMetric: metric, fields });
  const age = core.birthDay({ birthDay, today: day });
  const profile =
    sex && activity && goal && body.isValid && age.isValid && body.heightCm !== undefined && body.weightKg !== undefined
      ? { birthDay, sex, heightCm: body.heightCm, weightKg: body.weightKg, activityLevel: activity, goal }
      : undefined;
  const plan = profile ? core.dailyPlan({ ...profile, today: day }) : undefined;
  const factors = core.goalFactors();

  const canContinue: Record<Step, boolean> = {
    consent: consent,
    birthDate: age.isValid,
    sex: sex !== undefined,
    height: body.heightValid,
    weight: body.weightValid,
    activity: activity !== undefined,
    goal: goal !== undefined,
    result: plan !== undefined && !saving,
  };
  const index = steps.indexOf(step);

  async function advance() {
    if (!canContinue[step]) return;
    if (step !== "result") {
      setStep(steps[index + 1]);
      window.scrollTo(0, 0);
      return;
    }
    if (!profile || !plan) return;
    setSaving(true);
    try {
      await finishOnboarding(supabase, { userID, profile, targets: plan.targets, today: day, now: new Date() });
      onFinished();
    } catch {
      setSaveFailed(true);
    } finally {
      setSaving(false);
    }
  }

  // The row itself is the radio button, as an inline Picker row is one control on iOS.
  const choice = (title: string, detail: string | undefined, selected: boolean, onSelect: () => void) => (
    <button key={title} type="button" role="radio" aria-checked={selected} className="list-row list-row-button choice" onClick={onSelect}>
      <span className="choice-text">
        <span>{t(title)}</span>
        {detail && <span className="choice-detail">{detail}</span>}
      </span>
      {selected && (
        <svg className="checkmark" viewBox="0 0 14 12" aria-hidden="true">
          <path d="M1 6.5l4 4L13 1" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
    </button>
  );

  const numberRow = (label: string, field: keyof BodyFields, unit: string, id: string) => (
    <ListRow>
      <span className="number-row">
        <input
          className="text-field number-field"
          inputMode="decimal"
          placeholder={t(label)}
          aria-label={t(label)}
          data-testid={id}
          value={texts[field]}
          onChange={(event) => setTexts({ ...texts, [field]: event.target.value })}
        />
        <span className="secondary">{unit}</span>
      </span>
    </ListRow>
  );

  return (
    <main className="screen with-bottom-bar" data-screen="onboarding">
      <NavBar
        title={t(titles[step])}
        back={index > 0 ? t(titles[steps[index - 1]]) : undefined}
        onBack={index > 0 ? back : undefined}
      />
      <List>
        <div data-testid={`onboarding.step.${step}`}>
          {step === "consent" && (
            <>
              <ListSection>
                <ListRow>{t("consent.body")}</ListRow>
              </ListSection>
              <ListSection>
                <ListRow>
                  <label className="toggle-row">
                    <span>{t("consent.agree")}</span>
                    <input
                      type="checkbox"
                      role="switch"
                      className="switch"
                      data-testid="consent.agree"
                      checked={consent}
                      onChange={(event) => setConsent(event.target.checked)}
                    />
                  </label>
                </ListRow>
              </ListSection>
            </>
          )}
          {step === "birthDate" && (
            <ListSection footer={t("onboarding.birthDate.footer")}>
              <ListRow>
                <input
                  className="text-field"
                  type="date"
                  aria-label={t("onboarding.birthDate.label")}
                  data-testid="input.birthDate"
                  min="1900-01-01"
                  max={day}
                  value={birthDay}
                  onChange={(event) => isIsoDay(event.target.value) && setBirthDay(event.target.value)}
                />
              </ListRow>
            </ListSection>
          )}
          {step === "sex" && (
            <ListSection footer={t("onboarding.sex.footer")}>
              <div role="radiogroup" aria-label={t("onboarding.sex.title")}>
                {(["male", "female", "other"] as const).map((value) =>
                  choice(`onboarding.sex.${value}`, undefined, sex === value, () => setSex(value)),
                )}
              </div>
            </ListSection>
          )}
          {step === "height" && (
            <ListSection>
              {metric ? (
                numberRow("onboarding.height.field", "centimetres", "cm", "input.height")
              ) : (
                <>
                  {numberRow("onboarding.height.feet", "feet", "ft", "input.feet")}
                  {numberRow("onboarding.height.inches", "inches", "in", "input.inches")}
                </>
              )}
            </ListSection>
          )}
          {step === "weight" && (
            <ListSection>{numberRow("onboarding.weight.field", "weight", metric ? "kg" : "lb", "input.weight")}</ListSection>
          )}
          {step === "activity" && (
            <ListSection>
              <div role="radiogroup" aria-label={t("onboarding.activity.title")}>
                {(Object.keys(activityKeys) as Activity[]).map((level) =>
                  choice(activityKeys[level], t(`${activityKeys[level]}.detail`), activity === level, () => setActivity(level)),
                )}
              </div>
            </ListSection>
          )}
          {step === "goal" && (
            <ListSection>
              <div role="radiogroup" aria-label={t("onboarding.goal.title")}>
                {(Object.keys(goalKeys) as Goal[]).map((value) => {
                  const share = percent(Math.abs(factors[value] - 1));
                  const detail = value === "maintain" ? t("onboarding.goal.maintain.detail") : t(`${goalKeys[value]}.detail %@`, share);
                  return choice(goalKeys[value], detail, goal === value, () => setGoal(value));
                })}
              </div>
            </ListSection>
          )}
          {step === "result" && plan && (
            <ListSection header={<TargetsCard targets={plan.targets} shares={core.kcalShares(plan.targets)} />}>
              {plan.floorApplied && <ListRow>{t("targets.floor")}</ListRow>}
              {orderedWarnings(plan.warnings).map((warning) => (
                <ListRow key={warning}>{t(warningKeys[warning])}</ListRow>
              ))}
              <ListRow>{t("onboarding.result.footer")}</ListRow>
            </ListSection>
          )}
        </div>
      </List>
      <div className="bottom-bar">
        <div
          className="progress"
          role="img"
          aria-label={t("onboarding.progress %lld %lld", index + 1, steps.length)}
        >
          {steps.map((name, position) => (
            <span key={name} className={position <= index ? "progress-done" : ""} />
          ))}
        </div>
        {step === "birthDate" && !age.isAdult ? (
          <>
            <p className="footnote">{t("onboarding.underage.body")}</p>
            <SecondaryButton onClick={onDeleteAccount}>{t("onboarding.underage.delete")}</SecondaryButton>
          </>
        ) : (
          <PrimaryButton disabled={!canContinue[step]} onClick={() => void advance()} data-testid={`onboarding.continue.${step}`}>
            {t(step === "result" ? "onboarding.finish" : "onboarding.continue")}
          </PrimaryButton>
        )}
      </div>
      {saveFailed && <Alert title={t("error.server")} onClose={() => setSaveFailed(false)} />}
    </main>
  );
}
