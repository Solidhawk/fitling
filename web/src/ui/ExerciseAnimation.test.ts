import { afterEach, expect, test, vi } from "vitest";
import { loadManifest } from "./ExerciseAnimation";

afterEach(() => vi.unstubAllGlobals());

// bug-echo after S51: the build always ships the list of animations, so an answer that is not OK is a hiccup of the
// server. It is not kept: the next exercise screen asks again, instead of showing no animations until a reload.
test("aServerErrorIsNotKept", async () => {
  const answers = [
    new Response("", { status: 503 }),
    Response.json({ fps: 12, frames: 2, columns: 2, animations: { squat: [0, 1] } }),
  ];
  vi.stubGlobal("fetch", vi.fn(async () => answers.shift()));
  expect(await loadManifest()).toBeUndefined();
  expect((await loadManifest())?.animations.squat).toEqual([0, 1]);
});
