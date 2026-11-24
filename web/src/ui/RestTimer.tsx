import { useEffect, useState } from "react";
import { t } from "../i18n";

/** Counts down the rest after a set, in ink with card-coloured text, at the bottom of the workout (RestTimer on iOS). */
export function RestTimer({ endsAt, onSkip }: { endsAt: number; onSkip: () => void }) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const tick = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(tick);
  }, []);
  const remaining = Math.max(0, Math.ceil((endsAt - now) / 1000));
  const time = `${Math.floor(remaining / 60)}:${String(remaining % 60).padStart(2, "0")}`;
  return (
    <div className="rest-timer" data-testid="workout.rest">
      <span className="row-stack">
        <span className="rest-title">{t(remaining > 0 ? "training.rest.title" : "training.rest.done")}</span>
        <span className="rest-time" role="timer" aria-live="off">
          {time}
        </span>
      </span>
      <button type="button" className="rest-skip" onClick={onSkip}>
        {t(remaining > 0 ? "training.rest.skip" : "common.ok")}
      </button>
    </div>
  );
}
