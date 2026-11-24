import { expect, test } from "vitest";
import { fittingSize, largestCanvasPixels } from "./photos";

// Review: a photo of 24 or 48 megapixels from a recent iPhone is scaled down to fit the canvas of iOS Safari.
test("largePhotosAreScaledToFitTheCanvas", () => {
  expect(fittingSize(4032, 3024)).toEqual({ width: 4032, height: 3024 });
  const large = fittingSize(8064, 6048);
  expect(large.width * large.height).toBeLessThanOrEqual(largestCanvasPixels);
  expect(large.width / large.height).toBeCloseTo(8064 / 6048, 2);
  expect(fittingSize(5712, 4284).width * fittingSize(5712, 4284).height).toBeLessThanOrEqual(largestCanvasPixels);
});
