// How a partner is drawn, as Figures.swift does on iOS: the layers of one species and form stacked, the
// render zoomed so every form fills its frame with the feet on one ground line.

/** The figure's height as a share of the frame, per form. */
export const heights = [0.55, 0.6, 0.66, 0.72, 0.78, 0.84];
export const maxWidth = 0.94;
/** Where the feet stand, as a share of the frame height. */
export const ground = 0.93;
export const formCount = 6;
/** The colour variants as a turn of the body's hue, in degrees (PartnerLayers.hues). */
export const hues = [0, 40, 150, 210, 300];
/** What the partner wears, from back to front; the sweatband after a workout goes on last. */
const itemOrder = ["backpack", "scarf", "glasses", "bow", "cap", "crown"];

export interface Framing {
  scale: number;
  dx: number;
  dy: number;
}

/** `figure` is the render's bounds without its shadow: left, top, right, bottom, in image fractions. */
export function framing(figure: number[], form: number): Framing {
  const width = Math.max(figure[2] - figure[0], 0.01);
  const height = Math.max(figure[3] - figure[1], 0.01);
  const target = heights[Math.min(Math.max(form, 1), heights.length) - 1];
  const scale = Math.min(target / height, maxWidth / width);
  return { scale, dx: 0.5 - (scale * (figure[0] + figure[2])) / 2, dy: ground - scale * figure[3] };
}

/** Where a point of the render (in image fractions) lands in the frame. */
export function point(frame: Framing, x: number, y: number): { x: number; y: number } {
  return { x: frame.dx + frame.scale * x, y: frame.dy + frame.scale * y };
}

export interface PartnerLook {
  colorIndex?: number;
  mood?: string;
  growthStage?: number;
  trainedRecently?: boolean;
  items?: string[];
}

/** The rendered form (1...6) for a growth stage. */
export function form(growthStage: number): number {
  return Math.min(Math.max(growthStage, 0), formCount - 1) + 1;
}

export function hue(colorIndex: number): number {
  return hues[Math.min(Math.max(colorIndex, 0), hues.length - 1)];
}

/** The images that make up a partner in one look, from back to front. Only the body takes the colour. */
export function layers(species: string, look: PartnerLook): { name: string; takesColor: boolean }[] {
  const base = `partner-${species}-${form(look.growthStage ?? 0)}`;
  const stack = [
    { name: `${base}-body`, takesColor: true },
    { name: `${base}-face-${look.mood ?? "content"}`, takesColor: false },
  ];
  for (const item of itemOrder) {
    if (look.items?.includes(item)) stack.push({ name: `${base}-item-${item}`, takesColor: false });
  }
  if (look.trainedRecently) stack.push({ name: `${base}-item-sweatband`, takesColor: false });
  return stack;
}
