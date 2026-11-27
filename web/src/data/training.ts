import type { SupabaseClient } from "@supabase/supabase-js";
import type { IsoDay, Localized, TrainingInput } from "../core/fitlingCore";
import { failure } from "./failure";
import { allRows, type Keyset, type Row } from "./pages";

/** The training rows of the user and the shared catalogue, as FitlingCore reads them, plus what only the screens show. */
export type TrainingRows = Omit<TrainingInput, "userID" | "today" | "languages"> & {
  /** Per exercise id. */
  instructions: Record<string, Localized>;
  /** Per exercise id: barbell, dumbbell, machine, cable, kettlebell, band, bodyweight or other. */
  equipment: Record<string, string>;
};

const seconds = (value: unknown) => Date.parse(value as string) / 1000;
const optional = <T>(value: unknown) => (value === null || value === undefined ? undefined : (value as T));

/** Every row of `table`, page by page; `columns` names `id`, which the pages are read on from. */
function rows(client: SupabaseClient, table: string, columns: string, alive = true) {
  return allRows(() => {
    const query = client.from(table).select(columns);
    return (alive ? query.is("deleted_at", null) : query) as unknown as Keyset;
  });
}

/**
 * Everything the training tab reads (TrainingStore on iOS): shared and own exercises and programmes, the user's
 * settings, workouts and sets that are not deleted; programmes and days also when removed, as a past workout keeps
 * the name of its day. Row-level security keeps it to the user's own rows and the shared ones.
 */
export async function loadTraining(client: SupabaseClient): Promise<TrainingRows> {
  const [exercises, programs, days, items, settings, sessions, sets] = await Promise.all([
    rows(client, "exercises", "id, owner_id, name, instructions, kind, load_type, equipment, primary_muscles, secondary_muscles, default_step_kg"),
    rows(client, "programs", "id, owner_id, name, days_per_week, deleted_at", false),
    rows(client, "program_days", "id, program_id, owner_id, name, position, updated_at, deleted_at", false),
    rows(client, "program_exercises", "id, program_day_id, owner_id, exercise_id, position, target_sets, rep_min, rep_max, rest_seconds"),
    rows(client, "exercise_settings", "id, exercise_id, step_kg, rep_min, rep_max, updated_at"),
    rows(client, "workout_sessions", "id, program_day_id, performed_on, started_at, ended_at"),
    rows(client, "workout_sets", "id, session_id, exercise_id, position, weight_kg, reps, rpe, is_warmup"),
  ]);
  return {
    exercises: exercises.map((row) => ({
      id: row.id as string,
      ownerID: optional<string>(row.owner_id),
      name: row.name as Localized,
      kind: row.kind as string,
      loadType: row.load_type as string,
      primaryMuscles: row.primary_muscles as string[],
      secondaryMuscles: row.secondary_muscles as string[],
      defaultStepKg: Number(row.default_step_kg),
    })),
    instructions: Object.fromEntries(exercises.map((row) => [row.id as string, (row.instructions as Localized | null) ?? {}])),
    equipment: Object.fromEntries(exercises.map((row) => [row.id as string, row.equipment as string])),
    programs: programs.map((row) => ({
      id: row.id as string,
      ownerID: optional<string>(row.owner_id),
      name: row.name as Localized,
      daysPerWeek: row.days_per_week as number,
      deleted: row.deleted_at !== null,
    })),
    days: days.map((row) => ({
      id: row.id as string,
      programID: row.program_id as string,
      ownerID: optional<string>(row.owner_id),
      name: row.name as Localized,
      position: row.position as number,
      updatedAt: seconds(row.updated_at),
      deleted: row.deleted_at !== null,
    })),
    items: items.map((row) => ({
      id: row.id as string,
      programDayID: row.program_day_id as string,
      ownerID: optional<string>(row.owner_id),
      exerciseID: row.exercise_id as string,
      position: row.position as number,
      targetSets: row.target_sets as number,
      repMin: row.rep_min as number,
      repMax: row.rep_max as number,
      restSeconds: row.rest_seconds as number,
    })),
    settings: settings.map((row) => ({
      exerciseID: row.exercise_id as string,
      stepKg: Number(row.step_kg),
      repMin: optional<number>(row.rep_min),
      repMax: optional<number>(row.rep_max),
      updatedAt: seconds(row.updated_at),
    })),
    sessions: sessions.map((row) => ({
      id: row.id as string,
      programDayID: optional<string>(row.program_day_id),
      performedOn: row.performed_on as IsoDay,
      startedAt: seconds(row.started_at),
      endedAt: row.ended_at === null ? undefined : seconds(row.ended_at),
    })),
    sets: sets.map((row) => ({
      id: row.id as string,
      sessionID: row.session_id as string,
      exerciseID: row.exercise_id as string,
      position: row.position as number,
      weightKg: Number(row.weight_kg),
      reps: row.reps as number,
      rpe: row.rpe === null ? undefined : Number(row.rpe),
      isWarmup: row.is_warmup as boolean,
    })),
  };
}

/** The language a name the user types is stored under: the browser's first, as TrainingStore.language on iOS. */
export function typingLanguage(languages: readonly string[] = navigator.languages): string {
  return (languages[0] ?? "nl").slice(0, 2);
}

async function write(work: PromiseLike<{ error: { message: string } | null }>) {
  const { error } = await work;
  if (error) throw failure(error);
}

// MARK: Programmes

/** A new, empty programme of the user's own with one day per training day (TrainingStore.createProgram). */
export async function createProgram(
  client: SupabaseClient,
  userID: string,
  program: { name: string; daysPerWeek: number; dayName: (position: number) => string; language: string },
  now: Date,
): Promise<string> {
  const id = crypto.randomUUID();
  const days = Math.min(Math.max(program.daysPerWeek, 1), 7);
  const updated = now.toISOString();
  await write(client.from("programs").insert({ id, owner_id: userID, name: { [program.language]: program.name }, days_per_week: days, updated_at: updated }));
  await write(
    client.from("program_days").insert(
      Array.from({ length: days }, (_, position) => ({
        id: crypto.randomUUID(),
        program_id: id,
        owner_id: userID,
        name: { [program.language]: program.dayName(position + 1) },
        position,
        updated_at: updated,
      })),
    ),
  );
  return id;
}

/**
 * The user's own copy of a programme, to change freely (TrainingStore.copy): days and exercises with new ids; the
 * shared original stays as it is. `ids` gives each original row its new id and gets the ones it lacks: copying again
 * after a failure with the same map writes the same rows, so no second copy is made (UNFORGET S54).
 */
export async function copyProgram(
  client: SupabaseClient,
  userID: string,
  training: TrainingRows,
  programID: string,
  copy: { name: string; language: string },
  now: Date,
  ids: Map<string, string>,
): Promise<string> {
  const source = training.programs.find((program) => program.id === programID);
  if (!source) throw new Error("error.server");
  const newID = (original: string) => {
    const known = ids.get(original);
    if (known) return known;
    const made = crypto.randomUUID();
    ids.set(original, made);
    return made;
  };
  const id = newID(programID);
  const updated = now.toISOString();
  await write(
    client.from("programs").upsert({ id, owner_id: userID, name: { [copy.language]: copy.name }, days_per_week: source.daysPerWeek, deleted_at: null, updated_at: updated }),
  );
  const days = training.days.filter((day) => day.programID === programID && !day.deleted);
  const newDays = days.map((day) => ({
    old: day.id,
    row: { id: newID(day.id), program_id: id, owner_id: userID, name: day.name, position: day.position, deleted_at: null, updated_at: updated },
  }));
  if (newDays.length > 0) await write(client.from("program_days").upsert(newDays.map((day) => day.row)));
  const items = newDays.flatMap((day) =>
    training.items
      .filter((item) => item.programDayID === day.old)
      .map((item) => ({
        id: newID(item.id),
        program_day_id: day.row.id,
        owner_id: userID,
        exercise_id: item.exerciseID,
        position: item.position,
        target_sets: item.targetSets,
        rep_min: item.repMin,
        rep_max: item.repMax,
        rest_seconds: item.restSeconds,
        deleted_at: null,
        updated_at: updated,
      })),
  );
  if (items.length > 0) await write(client.from("program_exercises").upsert(items));
  return id;
}

export async function renameProgram(client: SupabaseClient, programID: string, name: string, language: string, now: Date) {
  await write(client.from("programs").update({ name: { [language]: name }, updated_at: now.toISOString() }).eq("id", programID));
}

/** Removed, not deleted: other devices learn of it through `deleted_at`. */
export async function deleteProgram(client: SupabaseClient, programID: string, now: Date) {
  const stamp = now.toISOString();
  await write(client.from("programs").update({ deleted_at: stamp, updated_at: stamp }).eq("id", programID));
}

/** An exercise at the end of a day of the user's own (TrainingStore.add); the picker keeps the values in range. */
export async function addItem(
  client: SupabaseClient,
  userID: string,
  item: { dayID: string; exerciseID: string; position: number; sets: number; repMin: number; repMax: number; restSeconds: number },
  now: Date,
) {
  await write(
    client.from("program_exercises").insert({
      id: crypto.randomUUID(),
      program_day_id: item.dayID,
      owner_id: userID,
      exercise_id: item.exerciseID,
      position: item.position,
      target_sets: item.sets,
      rep_min: item.repMin,
      rep_max: item.repMax,
      rest_seconds: item.restSeconds,
      updated_at: now.toISOString(),
    }),
  );
}

export async function removeItem(client: SupabaseClient, itemID: string, now: Date) {
  const stamp = now.toISOString();
  await write(client.from("program_exercises").update({ deleted_at: stamp, updated_at: stamp }).eq("id", itemID));
}

/** The user's own weight step for an exercise (TrainingStore.saveStep): one setting per exercise, changed in place. */
export async function saveStep(client: SupabaseClient, userID: string, exerciseID: string, stepKg: number, now: Date) {
  const step = Math.min(Math.max(stepKg, 0.25), 25);
  const { data, error } = await client
    .from("exercise_settings")
    .select("id")
    .eq("exercise_id", exerciseID)
    .is("deleted_at", null)
    .order("updated_at", { ascending: false })
    .limit(1);
  if (error) throw failure(error);
  const stamp = now.toISOString();
  if (data && data.length > 0) {
    await write(client.from("exercise_settings").update({ step_kg: step, updated_at: stamp }).eq("id", data[0].id as string));
  } else {
    await write(client.from("exercise_settings").insert({ id: crypto.randomUUID(), user_id: userID, exercise_id: exerciseID, step_kg: step, updated_at: stamp }));
  }
}

// MARK: Workouts

/** A workout of a programme day, or a free one (TrainingStore.start). */
export async function startWorkout(client: SupabaseClient, userID: string, dayID: string | undefined, today: IsoDay, now: Date): Promise<string> {
  const id = crypto.randomUUID();
  const stamp = now.toISOString();
  await write(
    client.from("workout_sessions").insert({ id, user_id: userID, program_day_id: dayID ?? null, performed_on: today, started_at: stamp, updated_at: stamp }),
  );
  return id;
}

/** A set as FitlingCore bounds it (`loggedSet`), after the last one of the workout; the workout is touched too. */
export async function logSet(
  client: SupabaseClient,
  userID: string,
  set: { sessionID: string; exerciseID: string; position: number; weightKg: number; reps: number; rpe?: number; isWarmup: boolean },
  now: Date,
): Promise<string> {
  const id = crypto.randomUUID();
  const stamp = now.toISOString();
  await write(
    client.from("workout_sets").insert({
      id,
      user_id: userID,
      session_id: set.sessionID,
      exercise_id: set.exerciseID,
      position: set.position,
      weight_kg: set.weightKg,
      reps: set.reps,
      rpe: set.rpe ?? null,
      is_warmup: set.isWarmup,
      updated_at: stamp,
    }),
  );
  await write(client.from("workout_sessions").update({ updated_at: stamp }).eq("id", set.sessionID));
  return id;
}

export async function removeSet(client: SupabaseClient, setID: string, now: Date) {
  const stamp = now.toISOString();
  await write(client.from("workout_sets").update({ deleted_at: stamp, updated_at: stamp }).eq("id", setID));
}

/** Ends a workout; never before it started (TrainingStore.finish). */
export async function finishWorkout(client: SupabaseClient, session: { id: string; startedAt: number }, now: Date) {
  const ended = new Date(Math.max(now.getTime(), session.startedAt * 1000)).toISOString();
  await write(client.from("workout_sessions").update({ ended_at: ended, updated_at: now.toISOString() }).eq("id", session.id));
}

/**
 * Throws a workout away with its sets, for one started by mistake (TrainingStore.discard), and what FitlingCore says
 * goes with it: a composed day made for this workout alone, its exercises, and with the last day its programme.
 */
export async function discardWorkout(
  client: SupabaseClient,
  sessionID: string,
  cleanup: { dayID?: string; itemIDs: string[]; programID?: string },
  now: Date,
) {
  const stamp = now.toISOString();
  const gone = { deleted_at: stamp, updated_at: stamp };
  await write(client.from("workout_sets").update(gone).eq("session_id", sessionID).is("deleted_at", null));
  await write(client.from("workout_sessions").update(gone).eq("id", sessionID));
  if (cleanup.itemIDs.length > 0) await write(client.from("program_exercises").update(gone).in("id", cleanup.itemIDs));
  if (cleanup.dayID) await write(client.from("program_days").update(gone).eq("id", cleanup.dayID));
  if (cleanup.programID) await write(client.from("programs").update(gone).eq("id", cleanup.programID));
}

/**
 * A composed workout as a new day in the user's own programme of composed workouts (TrainingStore.compose), with
 * the day id FitlingCore made for its focus; the programme is made the first time.
 */
export async function composeWorkout(
  client: SupabaseClient,
  userID: string,
  training: TrainingRows,
  plan: {
    dayID: string;
    programID?: string;
    exercises: { exerciseID: string; sets: number; repMin: number; repMax: number; restSeconds: number }[];
  },
  names: { program: string; day: string; language: string },
  now: Date,
): Promise<string> {
  const stamp = now.toISOString();
  let programID = plan.programID;
  if (!programID) {
    programID = crypto.randomUUID();
    await write(client.from("programs").insert({ id: programID, owner_id: userID, name: { [names.language]: names.program }, days_per_week: 1, updated_at: stamp }));
  }
  const positions = training.days.filter((day) => day.programID === programID && !day.deleted).map((day) => day.position);
  await write(
    client.from("program_days").insert({
      id: plan.dayID,
      program_id: programID,
      owner_id: userID,
      name: { [names.language]: names.day },
      position: Math.max(-1, ...positions) + 1,
      updated_at: stamp,
    }),
  );
  if (plan.exercises.length > 0) {
    await write(
      client.from("program_exercises").insert(
        plan.exercises.map((planned, position) => ({
          id: crypto.randomUUID(),
          program_day_id: plan.dayID,
          owner_id: userID,
          exercise_id: planned.exerciseID,
          position,
          target_sets: planned.sets,
          rep_min: planned.repMin,
          rep_max: planned.repMax,
          rest_seconds: planned.restSeconds,
          updated_at: stamp,
        })),
      ),
    );
  }
  return plan.dayID;
}
