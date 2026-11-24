import type { TrainingInput } from "../core/fitlingCore";
import type { TrainingRows } from "../data/training";
import { today } from "../day";

/** The rows as FitlingCore reads them, for today and the browser's languages. */
export function trainingInput(userID: string, rows: TrainingRows): TrainingInput {
  return { userID, today: today(), languages: [...navigator.languages], ...rows };
}
