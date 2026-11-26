import type { DayTotals, Targets } from "../core/fitlingCore";
import { decimal, grams, percent } from "../format";
import { t } from "../i18n";
import { FittedText } from "./FittedText";

type Props =
  /** The day's targets, each with its share of the kcal: full blocks. */
  | { targets: Targets; shares: { protein: number; carbs: number; fat: number }; eaten?: undefined }
  /** Eaten on the day against the targets: each block fills from the bottom. */
  | { targets: Targets; eaten: DayTotals; shares?: undefined };

/**
 * Protein, carbs and fat as three blocks side by side, like toy blocks, instead of the bars every food app uses
 * (MacroBlocks.swift); stacked when the text is very large.
 */
export function MacroBlocks(props: Props) {
  const { targets } = props;
  const blocks = [
    { key: "targets.protein", target: targets.proteinG, eaten: props.eaten?.proteinG, share: props.shares?.protein, fill: "var(--protein)" },
    { key: "targets.carbs", target: targets.carbsG, eaten: props.eaten?.carbsG, share: props.shares?.carbs, fill: "var(--carbs)" },
    { key: "targets.fat", target: targets.fatG, eaten: props.eaten?.fatG, share: props.shares?.fat, fill: "var(--fat)" },
  ];
  return (
    <div className="macro-blocks">
      {blocks.map((block) => {
        // The empty part is a pale tint of the colour on white, in dark mode too: the ink lettering needs a light ground.
        const filled = block.eaten === undefined ? 100 : Math.min(Math.max(block.eaten / Math.max(block.target, 1), 0), 1) * 100;
        const background = `linear-gradient(to top, ${block.fill} ${filled}%, color-mix(in srgb, ${block.fill} 35%, white) ${filled}%)`;
        return (
          <div className="macro-block" key={block.key} style={{ background }}>
            {/* Shrinks before it is cut short, as minimumScaleFactor(0.75) in MacroBlocks.swift: "Koolhydraten" on a phone. */}
            <FittedText className="macro-title" text={t(block.key)} minimumScale={0.75} />
            {block.eaten === undefined ? (
              <>
                <span className="macro-value">{grams(block.target)}</span>
                <span className="macro-detail">{t("targets.macro.share %@", percent(block.share ?? 0))}</span>
              </>
            ) : (
              <>
                <span className="macro-value">{decimal(Math.round(block.eaten), 0)}</span>
                <span className="macro-detail">{t("day.macro.of %@", decimal(block.target, 0))}</span>
              </>
            )}
          </div>
        );
      })}
    </div>
  );
}
