/** A day as Postgres writes it: "2026-11-18". */
export type IsoDay = string;

export interface DailyPlanInput {
  birthDay: IsoDay;
  sex: "male" | "female" | "other";
  heightCm: number;
  weightKg: number;
  activityLevel: "sedentary" | "light" | "moderate" | "active" | "very_active";
  goal: "lose" | "build_muscle" | "maintain" | "recomp";
  today: IsoDay;
}

export interface DailyPlan {
  bmr: number;
  tdee: number;
  targets: { kcal: number; proteinG: number; carbsG: number; fatG: number };
  floorApplied: boolean;
  warnings: string[];
}

/** The rules of FitlingCore, the same code as in the iOS app (D-24). */
export interface FitlingCore {
  dailyPlan(input: DailyPlanInput): DailyPlan;
}

export async function loadCore(_wasm: ArrayBuffer): Promise<FitlingCore> {
  throw new Error("FitlingCore is not loaded yet");
}
