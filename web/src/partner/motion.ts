/**
 * How the partner moves, as PartnerMotion in Figures.swift: it bobs, faster and higher with more energy, and only
 * breathes while asleep. `period` is one full bob in seconds, `lift` its height in percent of the frame, `squash` how
 * far the height swings around rest (the width swings the other way, so the partner keeps its volume).
 */
export interface Motion {
  period: number;
  lift: number;
  squash: number;
}

export function motion(energy: number, asleep: boolean): Motion {
  if (asleep) return { period: (2 * Math.PI) / 1.2, lift: 0, squash: 0.025 };
  const held = Math.min(Math.max(energy, 0), 1);
  return { period: (2 * Math.PI) / (2 + 4 * held), lift: 0.8 + 2.4 * held, squash: 0.02 };
}
