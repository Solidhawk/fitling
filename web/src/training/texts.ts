import type { Advice, PersonalRecord } from "../core/fitlingCore";
import { language, t } from "../i18n";
import { kilogramsPerPound } from "../units";

/** "62,5 kg" or "135 lb" in the user's number format, up to two decimals (WeightUnit.format on iOS). */
export function weight(kilograms: number, pounds: boolean): string {
  const value = pounds ? kilograms / kilogramsPerPound : kilograms;
  return `${new Intl.NumberFormat(language(), { maximumFractionDigits: 2 }).format(value)} ${pounds ? "lb" : "kg"}`;
}

/** What the advice says (ProgressionAdvice.text on iOS). */
export function adviceText(advice: Advice, pounds: boolean): string {
  const kg = weight(advice.weightKg ?? 0, pounds);
  switch (advice.kind) {
    case "findStartingWeight":
      return t("training.advice.start");
    case "keepGoing":
      return t("training.advice.keepGoing %@", kg);
    case "increase":
      return t("training.advice.increase %@", kg);
    case "addRepsFirst":
      return t("training.advice.addReps %lld %@", advice.targetReps ?? 0, kg);
    case "reduce":
      return t("training.advice.reduce %@", kg);
    case "easeBackIn":
      return t("training.advice.easeBack %@", kg);
    case "makeHarder":
      return t("training.advice.harder");
    case "makeEasier":
      return t("training.advice.easier");
  }
}

/** A record of a workout, to celebrate (PersonalRecord.text on iOS). */
export function recordText(exercise: string, record: PersonalRecord, pounds: boolean): string {
  switch (record.kind) {
    case "weight":
      return t("training.record.weight %@ %@", exercise, weight(record.kg, pounds));
    case "estimatedOneRepMax":
      return t("training.record.oneRepMax %@ %@", exercise, weight(record.kg, pounds));
    case "reps":
      return t("training.record.reps %@ %lld %@", exercise, record.count ?? 0, weight(record.kg, pounds));
  }
}

const focusKeys: Record<string, string> = {
  full_body: "training.focus.fullBody",
  upper_body: "training.focus.upperBody",
  lower_body: "training.focus.lowerBody",
  push: "training.focus.push",
  pull: "training.focus.pull",
  arms: "training.focus.arms",
};

export function focusTitle(focus: string): string {
  return t(focusKeys[focus] ?? focus);
}

export function muscleName(muscle: string): string {
  return t(`muscle.${muscle}`);
}

/** "Borst, Schouders en Triceps", as .formatted(.list(type: .and)). */
export function listed(names: string[]): string {
  return new Intl.ListFormat(language(), { type: "conjunction" }).format(names);
}

/** "18 nov." for a workout's start, as .formatted(date: .abbreviated, time: .omitted). */
export function shortDate(seconds: number): string {
  return new Intl.DateTimeFormat(language(), { day: "numeric", month: "short", year: "numeric" }).format(new Date(seconds * 1000));
}
