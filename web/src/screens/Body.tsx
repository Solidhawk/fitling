import { useCallback, useEffect, useRef, useState } from "react";
import type { FitlingCore, MeasurementKind } from "../core/fitlingCore";
import { addMeasurement, deleteMeasurement, loadMeasurements, type Measurement, measurementKinds } from "../data/body";
import { supabase } from "../data/supabase";
import { today } from "../day";
import { parseNumber } from "../format";
import { language, t } from "../i18n";
import { usesMetric } from "../units";
import { Alert } from "../ui/Alert";
import { LineChart } from "../ui/LineChart";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";
import { PickerRow } from "../ui/PickerRow";
import { SwipeRow } from "../ui/SwipeRow";

/**
 * Body weight and circumferences (BodyView on iOS): a chart of one kind, a row to add one and the earlier ones. The
 * user types in their own units; FitlingCore converts and bounds what is stored.
 */
export function Body({ core, userID, onBack }: { core: FitlingCore; userID: string; onBack: () => void }) {
  const metric = usesMetric();
  const [kind, setKind] = useState<MeasurementKind>("weight");
  const [measurements, setMeasurements] = useState<Measurement[]>([]);
  const [value, setValue] = useState("");
  // Undefined while the user leaves it at today: the day is then the one of the moment of adding, also past midnight
  // with the screen still open (UNFORGET S53). A day the user picked stays.
  const [picked, setPicked] = useState<string>();
  const [failed, setFailed] = useState<string>();
  const symbol = kind === "weight" ? (metric ? "kg" : "lb") : metric ? "cm" : "in";
  const shown = (measurement: Measurement) => core.measurementShown({ value: measurement.value, kind: measurement.kind, usesMetric: metric }).value ?? measurement.value;
  const typed = parseNumber(value);
  const stored = typed === undefined ? undefined : core.measurementStored({ value: typed, kind, usesMetric: metric }).value;

  const reload = useCallback(async () => {
    try {
      setMeasurements(await loadMeasurements(supabase, kind));
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
  }, [kind]);

  useEffect(() => {
    void reload();
  }, [reload]);

  async function act(work: () => Promise<unknown>) {
    try {
      await work();
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
    await reload();
  }

  // One measurement at a time: a double tap stores it once.
  const adding = useRef(false);
  function add() {
    if (stored === undefined || adding.current) return;
    adding.current = true;
    void act(async () => {
      const now = today();
      if (await addMeasurement(supabase, userID, { kind, value: stored, day: picked ?? now, today: now }, new Date())) setValue("");
    }).finally(() => {
      adding.current = false;
    });
  }

  const number = new Intl.NumberFormat(language(), { maximumFractionDigits: 1 });
  const date = new Intl.DateTimeFormat(language(), { day: "numeric", month: "long", year: "numeric" });
  return (
    <div className="tab-page pushed" data-page="body">
      <NavBar title={t("body.title")} back={t("training.title")} onBack={onBack} large />
      <List>
        <ListSection>
          <PickerRow label={t("body.kind")} value={kind} options={measurementKinds.map((option) => [option, t(`body.${option}`)])} onChange={setKind} />
          {measurements.length >= 2 && (
            <div className="list-row chart-row">
              <LineChart
                points={measurements.map((measurement) => ({ day: measurement.measuredOn, value: shown(measurement) }))}
                unit={symbol}
                label={t(`body.${kind}`)}
                height={180}
                showsPoints={false}
                includesZero={false}
              />
            </div>
          )}
        </ListSection>
        <ListSection header={t("body.new")}>
          <ListRow>
            <span className="value-field">
              <input
                className="text-field large-value"
                inputMode="decimal"
                aria-label={t("body.value")}
                placeholder={t("body.value")}
                data-testid="body.value"
                value={value}
                onChange={(event) => setValue(event.target.value)}
              />
              <span className="secondary">{symbol}</span>
            </span>
          </ListRow>
          <ListRow>
            <label className="labeled picker-row">
              <span>{t("body.date")}</span>
              <input
                className="picker"
                type="date"
                max={today()}
                value={picked ?? today()}
                onChange={(event) => setPicked(event.target.value === today() ? undefined : event.target.value)}
              />
            </label>
          </ListRow>
          <ListRow onClick={add} disabled={stored === undefined}>
            <span data-testid="body.add">{t("body.add")}</span>
          </ListRow>
        </ListSection>
        {measurements.length > 0 && (
          <ListSection header={t("body.history")}>
            {[...measurements].reverse().map((measurement) => (
              <SwipeRow key={measurement.id} deleteLabel={t("day.delete")} onDelete={() => void act(() => deleteMeasurement(supabase, measurement.id, new Date()))}>
                <span className="labeled-row" data-testid="body.measurement">
                  <span>{date.format(new Date(`${measurement.measuredOn}T12:00:00`))}</span>
                  <span className="value">{`${number.format(shown(measurement))} ${symbol}`}</span>
                </span>
              </SwipeRow>
            ))}
          </ListSection>
        )}
      </List>
      {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
    </div>
  );
}
