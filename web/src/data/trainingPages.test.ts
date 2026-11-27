import type { SupabaseClient } from "@supabase/supabase-js";
import { expect, test } from "vitest";
import { loadTraining } from "./training";

// Review Focus: a user with hundreds of workouts; every set counts for advice and records, also past 1000 rows.
test("manyWorkoutsAreReadInPages", async () => {
  const sets = Array.from({ length: 2500 }, (_, index) => ({
    id: String(index).padStart(5, "0"),
    session_id: "s",
    exercise_id: "e",
    position: index,
    weight_kg: "60.00",
    reps: 8,
    rpe: null,
    is_warmup: false,
  }));
  const client = {
    from(table: string) {
      let ordered = false;
      let after: string | undefined;
      const query = {
        select: () => query,
        is: () => query,
        gt(_column: string, value: string) {
          after = value;
          return query;
        },
        order(column: string) {
          ordered = column === "id";
          return query;
        },
        limit(count: number) {
          expect(ordered).toBe(true);
          const all = table === "workout_sets" ? sets : [];
          return Promise.resolve({ data: all.filter((row) => after === undefined || row.id > after).slice(0, Math.min(count, 1000)), error: null });
        },
      };
      return query;
    },
  } as unknown as SupabaseClient;
  const training = await loadTraining(client);
  expect(training.sets).toHaveLength(2500);
  // numeric comes back as text from PostgREST for large values; it is read as a number.
  expect(training.sets[0].weightKg).toBe(60);
});
