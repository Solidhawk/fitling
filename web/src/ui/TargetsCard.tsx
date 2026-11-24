import type { Targets } from "../core/fitlingCore";
import { kcal } from "../format";
import { t } from "../i18n";
import { MacroBlocks } from "./MacroBlocks";
import { NamePlate } from "./NamePlate";

/** The day's targets as one card: the energy target in heavy numerals, then a block per macro (TargetsCard.swift). */
export function TargetsCard({ targets, shares }: { targets: Targets; shares: { protein: number; carbs: number; fat: number } }) {
  return (
    <div className="card targets-card">
      <div className="stack-s">
        <NamePlate text={t("targets.kcal.label")} ribbon="var(--track)" edge={false} ink />
        <p className="kcal-total" data-testid="targets.kcal">
          {kcal(targets.kcal)}
        </p>
      </div>
      <MacroBlocks targets={targets} shares={shares} />
    </div>
  );
}
