// How long the user wants to train, kept for the next time on this device (TrainingViewModel.workoutMinutes).
const key = "fitling.workoutMinutes";

export function rememberedMinutes(choices: { durations: number[]; defaultMinutes: number }): number {
  try {
    const remembered = Number(localStorage.getItem(key));
    return choices.durations.includes(remembered) ? remembered : choices.defaultMinutes;
  } catch {
    return choices.defaultMinutes;
  }
}

export function rememberMinutes(minutes: number) {
  try {
    localStorage.setItem(key, String(minutes));
  } catch {
    // Private mode: the choice holds for this visit only.
  }
}
