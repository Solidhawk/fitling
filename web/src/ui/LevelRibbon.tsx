import { t } from "../i18n";

/**
 * The level and the way to the next one, as a ribbon that fills up (LevelRibbon in PartnerTabView.swift). Level and
 * XP sit side by side and wrap under each other when the text is large.
 */
export function LevelRibbon({ level, xpIntoLevel, xpForNextLevel }: { level: number; xpIntoLevel: number; xpForNextLevel: number }) {
  const fraction = xpForNextLevel > 0 ? Math.min(Math.max(xpIntoLevel / xpForNextLevel, 0), 1) : 1;
  return (
    <div className="level-ribbon">
      <div className="level-ribbon-row">
        <span className="level-ribbon-level">{t("partner.level %lld", level)}</span>
        {xpForNextLevel > 0 && <span className="level-ribbon-xp">{t("partner.xp.progress %lld %lld", xpIntoLevel, xpForNextLevel)}</span>}
      </div>
      <div className="level-ribbon-track" aria-hidden="true">
        {/* At least as wide as it is high once there is any XP, so a little progress still shows as a pill. */}
        <div className="level-ribbon-fill" style={{ width: fraction > 0 ? `max(${fraction * 100}%, 12px)` : 0 }} />
      </div>
      {xpForNextLevel === 0 && <span className="level-ribbon-max">{t("partner.level.max")}</span>}
    </div>
  );
}
