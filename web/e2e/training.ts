import { expect, type Page } from "@playwright/test";
import { admin, createUser, localDay, nl, signIn } from "./users";

// Helpers for the training tests: the shared catalogue of supabase/seed/sport.sql and workouts stored as an iPhone
// would have synced them.

export function daysBefore(count: number): string {
  const date = new Date();
  date.setDate(date.getDate() - count);
  return localDay(date);
}

/** A shared exercise by its English name, with its Dutch one. */
export async function exercise(english: string): Promise<{ id: string; name: string }> {
  const { data, error } = await admin.from("exercises").select("id, name").is("owner_id", null);
  if (error) throw error;
  const found = data.find((row) => (row.name as Record<string, string>).en === english);
  if (!found) throw new Error(`no exercise ${english}`);
  return { id: found.id as string, name: (found.name as Record<string, string>).nl };
}

/** The ready-made programme with the fewest days, as the tab lists it first, with its days in order. */
export async function firstProgramme(): Promise<{ id: string; name: string; days: { id: string; name: string }[] }> {
  const programs = await admin.from("programs").select("id, name, days_per_week").is("owner_id", null).is("deleted_at", null);
  if (programs.error) throw programs.error;
  const program = [...programs.data].sort(
    (a, b) => a.days_per_week - b.days_per_week || (a.name as Record<string, string>).nl.localeCompare((b.name as Record<string, string>).nl),
  )[0];
  const days = await admin.from("program_days").select("id, name, position").eq("program_id", program.id).is("deleted_at", null).order("position");
  if (days.error) throw days.error;
  return {
    id: program.id as string,
    name: (program.name as Record<string, string>).nl,
    days: days.data.map((day) => ({ id: day.id as string, name: (day.name as Record<string, string>).nl })),
  };
}

/** A finished workout `daysAgo` with working sets of one exercise: weight in kg and reps. */
export async function finishedWorkout(userID: string, exerciseID: string, daysAgo: number, sets: [number, number][], dayID?: string) {
  const started = new Date(Date.now() - daysAgo * 86_400_000);
  const id = crypto.randomUUID();
  const session = await admin.from("workout_sessions").insert({
    id,
    user_id: userID,
    program_day_id: dayID ?? null,
    performed_on: daysBefore(daysAgo),
    started_at: started.toISOString(),
    ended_at: new Date(started.getTime() + 3_600_000).toISOString(),
    updated_at: started.toISOString(),
  });
  if (session.error) throw session.error;
  const rows = sets.map(([weight, reps], position) => ({
    id: crypto.randomUUID(),
    user_id: userID,
    session_id: id,
    exercise_id: exerciseID,
    position,
    weight_kg: weight,
    reps,
    rpe: 7,
    is_warmup: false,
    updated_at: started.toISOString(),
  }));
  const stored = await admin.from("workout_sets").insert(rows);
  if (stored.error) throw stored.error;
  return id;
}

/** Signed in with a profile and a partner, on the training tab. */
export async function openTraining(page: Page, prepare?: (userID: string) => Promise<void>) {
  const user = await createUser({ profile: true, creature: true });
  await prepare?.(user.id);
  await signIn(page, user.email);
  await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
  await page.getByRole("tab", { name: nl("training.title") }).click();
  await expect(page.getByTestId("training.compose")).toBeVisible({ timeout: 15_000 });
  return user;
}

/**
 * Taps a row of the training tab by its name, first scrolled to the middle of the screen: scrolled only into view, a
 * low row lies under the tab bar, which takes the tap.
 */
export async function tapRow(page: Page, name: string) {
  const row = page.getByRole("button", { name });
  await row.evaluate((element) => element.scrollIntoView({ block: "center" }));
  await row.click();
}
