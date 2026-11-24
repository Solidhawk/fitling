import anchors from "../generated/partnerAnchors.json";
import { framing, form, hue, layers, type PartnerLook } from "./framing";
import type { Species } from "./species";

const allAnchors = anchors as Record<string, { figure: number[] } | undefined>;
const startShape = 0.3;

/**
 * A partner in one look, standing still: its layers stacked in a square, as PartnerCanvas in Figures.swift.
 * Hidden from screen readers; the name next to it says who it is.
 */
export function PartnerCanvas({ species, look = {} }: { species: Species; look?: PartnerLook & { bodyShape?: number } }) {
  const anchor = allAnchors[`${species}/${form(look.growthStage ?? 0)}`];
  const frame = anchor ? framing(anchor.figure, form(look.growthStage ?? 0)) : { scale: 1, dx: 0, dy: 0 };
  // Wider when round: about 92 % when lean, 120 % when round (PartnerLook.width).
  const width = 1 + (Math.min(Math.max(look.bodyShape ?? startShape, 0), 1) - startShape) * 0.28;
  return (
    <div className="partner-canvas" aria-hidden="true">
      <div className="partner-canvas-body" style={{ transform: `scaleX(${width})` }}>
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
      </div>
    </div>
  );
}
