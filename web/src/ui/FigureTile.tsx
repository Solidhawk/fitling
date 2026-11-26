import { t } from "../i18n";
import { PartnerCanvas } from "../partner/PartnerCanvas";
import type { Species } from "../partner/species";

/** One partner in the welcome catalog on its pastel ground; read as its name and its line of character. */
export function FigureTile({ species }: { species: Species }) {
  return (
    <div
      className="figure-tile"
      role="img"
      aria-label={t(`creature.${species}.name`)}
      aria-description={t(`creature.${species}.note`)}
      style={{ backgroundColor: `var(--partner-tint-${species})` }}
    >
      <PartnerCanvas species={species} />
    </div>
  );
}
