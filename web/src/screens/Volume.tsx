import { useState } from "react";
import type { FitlingCore, TrainingInput } from "../core/fitlingCore";
import { language, t } from "../i18n";
import { muscleName } from "../training/texts";
import { List, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";
import { Segmented } from "../ui/Segmented";

/** Working sets per muscle in this week or the last, as bars in ink with their number beside them (VolumeView on iOS). */
export function Volume({ core, input, onBack }: { core: FitlingCore; input: TrainingInput; onBack: () => void }) {
  const [lastWeek, setLastWeek] = useState(false);
  const bars = core.weeklyVolume({ training: input, lastWeek });
  const most = Math.max(1, ...bars.map((bar) => bar.sets));
  const number = new Intl.NumberFormat(language(), { maximumFractionDigits: 1 });
  return (
    <div className="tab-page pushed" data-page="volume">
      <NavBar title={t("training.progress.volume")} back={t("training.title")} onBack={onBack} large />
      <List>
        <ListSection footer={t("training.volume.footer")}>
          <div className="list-row">
            <Segmented
              label={t("training.volume.week")}
              value={lastWeek ? "last" : "this"}
              options={[
                ["this", t("training.volume.thisWeek")],
                ["last", t("training.volume.lastWeek")],
              ]}
              onChange={(value) => setLastWeek(value === "last")}
            />
          </div>
          <div className="list-row volume-chart" data-testid="volume.chart">
            {bars.length === 0 ? (
              <span className="footnote secondary">{t("training.volume.empty")}</span>
            ) : (
              <dl className="bars">
                {bars.map((bar) => (
                  <div key={bar.muscle} className="bar-row">
                    <dt>{muscleName(bar.muscle)}</dt>
                    <dd>
                      <span className="bar" style={{ width: `${(bar.sets / most) * 100}%` }} />
                      <span className="bar-value">{number.format(bar.sets)}</span>
                    </dd>
                  </div>
                ))}
              </dl>
            )}
          </div>
        </ListSection>
      </List>
    </div>
  );
}
