import { afterEach, expect, test, vi } from "vitest";
import { core } from "./useCore";

afterEach(() => vi.unstubAllGlobals());

// A failed download (a weak connection) is not kept: trying again downloads again.
test("after a failed download the rules are fetched again", async () => {
  const fetch = vi.fn(async () => new Response(null, { status: 503 }));
  vi.stubGlobal("fetch", fetch);
  await expect(core()).rejects.toThrow("fitling-core: 503");
  await expect(core()).rejects.toThrow("fitling-core: 503");
  expect(fetch).toHaveBeenCalledTimes(2);
});
