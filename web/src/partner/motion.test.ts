import { expect, test } from "vitest";
import { motion } from "./motion";

// PartnerMotion in Figures.swift: the phase runs at 2 + 4·energy per second, the bob is 0.8 + 2.4·energy % high.
test("aLivelyPartnerBobsFasterAndHigher", () => {
  const tired = motion(0, false);
  const lively = motion(1, false);
  expect(tired).toEqual({ period: (2 * Math.PI) / 2, lift: 0.8, squash: 0.02 });
  expect(lively.period).toBeCloseTo((2 * Math.PI) / 6);
  expect(lively.lift).toBeCloseTo(3.2);
  expect(motion(0.5, false).lift).toBeCloseTo(2);
  // Energy outside 0...1 is held to it, as on iOS.
  expect(motion(7, false)).toEqual(lively);
  expect(motion(-1, false)).toEqual(tired);
});

test("aSleepingPartnerOnlyBreathes", () => {
  expect(motion(1, true)).toEqual({ period: (2 * Math.PI) / 1.2, lift: 0, squash: 0.025 });
});
