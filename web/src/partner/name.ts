import { limitedText } from "../text";

/** The check on creatures.name: Postgres counts code points, so a name is limited by its Unicode scalars. */
export const nameLimit = 24;

/**
 * While typing: cut off at the limit by whole characters, keep spaces (PartnerSetupViewModel.limited). An emoji
 * made of five scalars takes five of the 24.
 */
export function limitedName(name: string): string {
  return limitedText(name, nameLimit);
}

/** What is stored: trimmed, limited, trimmed again. */
export function cleanedName(name: string): string {
  return limitedName(name.trim()).trim();
}
