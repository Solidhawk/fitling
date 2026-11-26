import { removeAllPhotos } from "./photos";

const key = "fitling-photos-owner";

/**
 * Progress photos belong to the account that took them: when another user signs in on this browser they go, as
 * RootViewModel on iOS erases them for another user. A session that could not be refreshed at start is not a reason:
 * the same user keeps them.
 */
export async function keepPhotosFor(
  userID: string,
  storage: Pick<Storage, "getItem" | "setItem"> = localStorage,
  wipe: () => Promise<void> = removeAllPhotos,
): Promise<void> {
  let owner: string | null = null;
  try {
    owner = storage.getItem(key);
  } catch {
    owner = null;
  }
  if (owner !== null && owner !== userID) await wipe();
  try {
    storage.setItem(key, userID);
  } catch {
    // Private mode: nothing is kept between visits anyway.
  }
}
