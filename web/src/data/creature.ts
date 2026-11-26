import type { SupabaseClient } from "@supabase/supabase-js";
import type { CreatureStateInput } from "../core/fitlingCore";
import type { Species } from "../partner/species";
import { failure } from "./failure";

/** The user's partner as stored: what FitlingCore needs for its mood, plus its name and what it wears. */
export interface Partner {
  species: Species;
  name: string;
  state: CreatureStateInput;
  items: string[];
}

export async function loadPartner(client: SupabaseClient, userID: string): Promise<Partner | undefined> {
  const { data, error } = await client
    .from("creatures")
    .select("species, name, color_index, tone, created_on, body_shape, xp, last_processed_on, off_target_days, equipped_items")
    .eq("user_id", userID)
    .maybeSingle();
  if (error) throw failure(error);
  if (!data) return undefined;
  return {
    species: data.species as Species,
    name: data.name as string,
    items: (data.equipped_items as string[] | null) ?? [],
    state: {
      species: data.species as string,
      colorIndex: data.color_index as number,
      tone: data.tone as string,
      createdOn: data.created_on as string,
      bodyShape: Number(data.body_shape),
      xp: data.xp as number,
      lastProcessedDay: (data.last_processed_on as string | null) ?? undefined,
      offTargetDays: data.off_target_days as number,
    },
  };
}
