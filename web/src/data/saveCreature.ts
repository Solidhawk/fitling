import type { SupabaseClient } from "@supabase/supabase-js";
import type { Species } from "../partner/species";

export type Tone = "sweet" | "funny" | "coach";

export interface NewPartner {
  userID: string;
  species: Species;
  name: string;
  colorIndex: number;
  tone: Tone;
  startShape: number;
  today: string;
  now: Date;
}

export function creatureRow(partner: NewPartner) {
  return {
    user_id: partner.userID,
    species: partner.species,
    name: partner.name,
    color_index: partner.colorIndex,
    tone: partner.tone,
    created_on: partner.today,
    body_shape: partner.startShape,
    updated_at: partner.now.toISOString(),
  };
}

/**
 * Stores the partner. When one already exists for this user (another device made one meanwhile), that one is kept,
 * as PartnerSetupViewModel.save does.
 */
export async function saveCreature(client: SupabaseClient, partner: NewPartner): Promise<void> {
  const { error } = await client.from("creatures").upsert(creatureRow(partner), { onConflict: "user_id", ignoreDuplicates: true });
  if (error) throw new Error("error.server");
}
