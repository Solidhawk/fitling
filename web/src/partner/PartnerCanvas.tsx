import type { CSSProperties } from "react";
import anchors from "../generated/partnerAnchors.json";
import { type Framing, framing, form, hue, layers, type PartnerLook, point } from "./framing";
import { motion } from "./motion";
import type { Species } from "./species";

interface Anchor {
  figure: number[];
  headTop: number[];
  headCenter: number[];
  headRadius: number;
}

const allAnchors = anchors as Record<string, Anchor | undefined>;
const startShape = 0.3;

/**
 * A partner in one look: its layers stacked in a square, as PartnerCanvas in Figures.swift. With `energy` it moves as
 * PartnerFigure does (it bobs, or breathes while asleep); without it, it stands still. With reduced motion it always
 * stands still. Hidden from screen readers; the name next to it says who it is.
 */
export function PartnerCanvas({
  species,
  look = {},
  energy,
}: {
  species: Species;
  look?: PartnerLook & { bodyShape?: number };
  /** 0 is tired, 1 is full of energy (the snapshot's energy). */
  energy?: number;
}) {
  const anchor = allAnchors[`${species}/${form(look.growthStage ?? 0)}`];
  const frame = anchor ? framing(anchor.figure, form(look.growthStage ?? 0)) : { scale: 1, dx: 0, dy: 0 };
  // Wider when round: about 92 % when lean, 120 % when round (PartnerLook.width).
  const width = 1 + (Math.min(Math.max(look.bodyShape ?? startShape, 0), 1) - startShape) * 0.28;
  const asleep = look.mood === "asleep";
  const moving = energy === undefined ? undefined : motion(energy, asleep);
  const body: CSSProperties & Record<`--${string}`, string | number> = { transform: `scaleX(${width})` };
  if (moving) {
    body["--partner-period"] = `${moving.period}s`;
    body["--partner-lift"] = moving.lift;
    body["--partner-squash"] = moving.squash;
  }
  return (
    <div className="partner-canvas" aria-hidden="true">
      <div className={moving ? "partner-canvas-body partner-moving" : "partner-canvas-body"} style={body}>
        <div
          className="partner-canvas-render"
          style={{ left: `${frame.dx * 100}%`, top: `${frame.dy * 100}%`, width: `${frame.scale * 100}%`, height: `${frame.scale * 100}%` }}
        >
          {layers(species, look).map((layer) => (
            <img
              key={layer.name}
              src={`${import.meta.env.BASE_URL}partners/${layer.name}.png`}
              alt=""
              draggable={false}
              style={layer.takesColor && hue(look.colorIndex ?? 0) !== 0 ? { filter: `hue-rotate(${hue(look.colorIndex ?? 0)}deg)` } : undefined}
            />
          ))}
        </div>
        {asleep && anchor && <SleepingZs anchor={anchor} frame={frame} />}
      </div>
    </div>
  );
}

/** Two Z's rising from the head of a sleeping partner (SleepingZs in Figures.swift), in fractions of the frame. */
function SleepingZs({ anchor, frame }: { anchor: Anchor; frame: Framing }) {
  const top = point(frame, anchor.headCenter[0] + anchor.headRadius * 0.9, anchor.headTop[1]);
  return (
    <svg className="partner-zs" viewBox="0 0 1 1" preserveAspectRatio="none">
      <Letter x={top.x} y={top.y} size={0.09} />
      <Letter x={top.x + 0.09} y={top.y - 0.09} size={0.06} />
    </svg>
  );
}

function Letter({ x, y, size }: { x: number; y: number; size: number }) {
  const left = x - size / 2;
  const top = y - size / 2;
  return (
    <path
      d={`M${left} ${top}H${left + size}L${left} ${top + size}H${left + size}`}
      vectorEffect="non-scaling-stroke"
      // At least 1.5 px, as on iOS; otherwise a sixth of the letter (the frame is the container).
      style={{ strokeWidth: `max(1.5px, ${size * 16}cqw)` }}
    />
  );
}
