import { expect, test } from "vitest";
import { framing, ground, heights, layers, maxWidth, point } from "./framing";

// The cases of FigureTests.swift (PartnerFramingTests and PartnerLayersTests).
test("a small figure is zoomed to its form's height with its feet on the ground", () => {
  const frame = framing([0.42, 0.6, 0.62, 0.84], 1);
  expect(frame.scale * 0.24).toBeCloseTo(heights[0], 3);
  expect(point(frame, 0.52, 0.84).x).toBeCloseTo(0.5, 3);
  expect(point(frame, 0.52, 0.84).y).toBeCloseTo(ground, 3);
});

test("a wide figure is zoomed only as far as it fits", () => {
  expect(framing([0.05, 0.1, 0.95, 0.9], 6).scale * 0.9).toBeLessThanOrEqual(maxWidth + 0.001);
});

test("the stack starts with the body and the face of the mood", () => {
  expect(layers("owl", { mood: "hungry", growthStage: 3 }).map((layer) => layer.name)).toEqual(["partner-owl-4-body", "partner-owl-4-face-hungry"]);
});

test("items go on in a fixed order and the sweatband last; only the body takes the colour", () => {
  const stack = layers("frog", { trainedRecently: true, items: ["crown", "backpack", "glasses"] });
  expect(stack.slice(2).map((layer) => layer.name)).toEqual([
    "partner-frog-1-item-backpack",
    "partner-frog-1-item-glasses",
    "partner-frog-1-item-crown",
    "partner-frog-1-item-sweatband",
  ]);
  expect(stack.map((layer) => layer.takesColor)).toEqual([true, false, false, false, false, false]);
});
