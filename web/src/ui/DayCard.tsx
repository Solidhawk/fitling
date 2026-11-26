import type { DayTotals, PartnerSnapshot, Targets } from "../core/fitlingCore";
import type { Partner } from "../data/creature";
import { decimal, kcal } from "../format";
import { t } from "../i18n";
import { PartnerCanvas } from "../partner/PartnerCanvas";
import { FittedText } from "./FittedText";
import { MacroBlocks } from "./MacroBlocks";
import { NamePlate } from "./NamePlate";

/**
 * The day as a card in the partner's colour: the partner, the kcal still to go, and the macros as blocks that fill up
 * (DayCard in DayView.swift). Without a partner the card is plain white.
 */
export function DayCard({ totals, targets, partner, snapshot }: { totals: DayTotals; targets: Targets; partner?: Partner; snapshot?: PartnerSnapshot }) {
  const remaining = targets.kcal - totals.kcal;
  const species = partner?.species;
  return (
    <div
      className={species ? "card day-card day-card-partner" : "card day-card"}
      data-testid="day.progress"
      style={species ? { backgroundColor: `var(--partner-tint-${species})` } : undefined}
    >
      <div className="day-card-header">
        {partner && snapshot && (
          <div className="day-card-figure">
            <PartnerCanvas
              species={partner.species}
              look={{
                colorIndex: snapshot.colorIndex,
                mood: snapshot.mood,
                growthStage: snapshot.growthStage,
                bodyShape: snapshot.bodyShape,
                trainedRecently: snapshot.trainedRecently,
                items: partner.items,
              }}
              energy={snapshot.energy}
            />
          </div>
        )}
        <div className="day-card-numbers">
          {partner && <NamePlate text={partner.name} ribbon={`var(--partner-ribbon-${partner.species})`} edge={false} />}
          <FittedText className="day-card-remaining" text={decimal(Math.round(Math.abs(remaining)), 0)} minimumScale={0.7} />
          <span className="day-card-label">{t(remaining >= 0 ? "day.kcal.toGo" : "day.kcal.overTarget")}</span>
          <span className="day-card-eaten">{t("day.kcal.eatenOf %@ %@", kcal(totals.kcal), kcal(targets.kcal))}</span>
        </div>
      </div>
      {partner && snapshot && <p className="day-card-mood">{t(`partner.mood.${snapshot.mood} %@`, partner.name)}</p>}
      <MacroBlocks eaten={totals} targets={targets} />
    </div>
  );
}
