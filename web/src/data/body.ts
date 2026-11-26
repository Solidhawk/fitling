import type { SupabaseClient } from "@supabase/supabase-js";
import type { IsoDay, MeasurementKind } from "../core/fitlingCore";
import { failure } from "./failure";

export const measurementKinds: MeasurementKind[] = ["weight", "waist", "chest", "hips", "arm", "thigh", "neck"];

/** One measurement as stored: kilograms for weight, centimetres for the rest. */
export interface Measurement {
  id: string;
  measuredOn: IsoDay;
  kind: MeasurementKind;
  value: number;
}

/** Oldest first, so a chart can draw them in order (BodyLog.measurements). */
export async function loadMeasurements(client: SupabaseClient, kind: MeasurementKind): Promise<Measurement[]> {
  const { data, error } = await client
    .from("body_measurements")
    .select("id, measured_on, kind, value")
    .eq("kind", kind)
    .is("deleted_at", null)
    .order("measured_on")
    .order("updated_at");
  if (error) throw failure(error);
  return (data ?? []).map((row) => ({ id: row.id as string, measuredOn: row.measured_on as IsoDay, kind: row.kind as MeasurementKind, value: Number(row.value) }));
}

/**
 * A measurement on a day up to today, with the value FitlingCore stored it as (`measurementStored`); nothing for a
 * day still to come (BodyLog.add).
 */
export async function addMeasurement(
  client: SupabaseClient,
  userID: string,
  measurement: { kind: MeasurementKind; value: number; day: IsoDay; today: IsoDay },
  now: Date,
): Promise<boolean> {
  if (measurement.day > measurement.today) return false;
  const { error } = await client.from("body_measurements").insert({
    id: crypto.randomUUID(),
    user_id: userID,
    measured_on: measurement.day,
    kind: measurement.kind,
    value: measurement.value,
    updated_at: now.toISOString(),
  });
  if (error) throw failure(error);
  return true;
}

export async function deleteMeasurement(client: SupabaseClient, id: string, now: Date) {
  const stamp = now.toISOString();
  const { error } = await client.from("body_measurements").update({ deleted_at: stamp, updated_at: stamp }).eq("id", id);
  if (error) throw failure(error);
}
