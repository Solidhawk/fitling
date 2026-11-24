import { t } from "../i18n";
import { hue } from "../partner/framing";
import type { Species } from "../partner/species";
import { LockFill } from "./Symbols";

/**
 * The partner's body colours as round swatches, the chosen one ringed in ink (ColorSwatches in PartnerSetupView.swift).
 * After the `count` free ones come the locked ones, with a lock and the level at which they unlock.
 */
export function ColorSwatches({
  species,
  count,
  selection,
  onSelect,
  unlockLevels = [],
  label,
}: {
  species: Species;
  count: number;
  selection: number;
  onSelect: (index: number) => void;
  unlockLevels?: number[];
  label: string;
}) {
  return (
    <span className="swatches" role="radiogroup" aria-label={label}>
      {Array.from({ length: count + unlockLevels.length }, (_, index) => {
        const locked = index >= count;
        return (
          <button
            key={index}
            type="button"
            role="radio"
            aria-checked={selection === index}
            aria-label={locked ? t("partner.color.locked %lld %lld", index + 1, unlockLevels[index - count]) : t("partner.color %lld", index + 1)}
            className="swatch"
            disabled={locked}
            onClick={() => onSelect(index)}
          >
            <span className="swatch-fill" style={{ backgroundColor: `var(--partner-ribbon-${species})`, filter: `hue-rotate(${hue(index)}deg)` }} />
            {locked && (
              <span className="swatch-lock">
                <LockFill size={15} />
              </span>
            )}
          </button>
        );
      })}
    </span>
  );
}
