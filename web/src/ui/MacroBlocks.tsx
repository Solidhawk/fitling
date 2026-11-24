import type { Targets } from "../core/fitlingCore";
import { grams, percent } from "../format";
import { t } from "../i18n";

/**
 * Protein, carbs and fat as three blocks side by side, each its target in grams and its share of the day's kcal
 * (MacroBlocks.swift); stacked when the text is very large.
 */
export function MacroBlocks({ targets, shares }: { targets: Targets; shares: { protein: number; carbs: number; fat: number } }) {
  const blocks = [
    { key: "targets.protein", grams: targets.proteinG, share: shares.protein, fill: "var(--protein)" },
    { key: "targets.carbs", grams: targets.carbsG, share: shares.carbs, fill: "var(--carbs)" },
    { key: "targets.fat", grams: targets.fatG, share: shares.fat, fill: "var(--fat)" },
  ];
  return (
    <div className="macro-blocks">
      {blocks.map((block) => (
        <div className="macro-block" key={block.key} style={{ backgroundColor: block.fill }}>
          <span className="macro-title">{t(block.key)}</span>
          <span className="macro-value">{grams(block.grams)}</span>
          <span className="macro-detail">{t("targets.macro.share %@", percent(block.share))}</span>
        </div>
      ))}
    </div>
  );
}
