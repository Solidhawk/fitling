import { expect, test } from "vitest";
import { keepPhotosFor } from "./photoOwner";

function memory(): Pick<Storage, "getItem" | "setItem"> {
  const values = new Map<string, string>();
  return { getItem: (key) => values.get(key) ?? null, setItem: (key, value) => void values.set(key, value) };
}

// Review: photos are not wiped when the session could not be refreshed at start; only for another user (as
// RootViewModel on iOS) or on signing out on request.
test("photosStayForTheSameUserAndGoForAnother", async () => {
  const storage = memory();
  let wiped = 0;
  const wipe = async () => {
    wiped++;
  };
  await keepPhotosFor("user-a", storage, wipe);
  expect(wiped).toBe(0);
  await keepPhotosFor("user-a", storage, wipe);
  expect(wiped).toBe(0);
  await keepPhotosFor("user-b", storage, wipe);
  expect(wiped).toBe(1);
});
