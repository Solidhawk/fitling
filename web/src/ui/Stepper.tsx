import { Minus, Plus } from "lucide-react";
import { t } from "../i18n";

/**
 * A Stepper in a list row: the label on the left, minus and plus on the right, each disabled at its end of the range.
 * The label says the value ("Sets: 3"), so a screen reader hears it with every step.
 */
export function Stepper({
  label,
  value,
  min,
  max,
  step = 1,
  onChange,
  testID,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step?: number;
  onChange: (value: number) => void;
  testID?: string;
}) {
  const set = (next: number) => onChange(Math.min(Math.max(Math.round(next / step) * step, min), max));
  return (
    <div className="stepper-row" data-testid={testID}>
      <span className="stepper-label" aria-live="polite">
        {label}
      </span>
      <span className="stepper" role="group" aria-label={label}>
        <button type="button" aria-label={t("common.decrease")} disabled={value <= min} onClick={() => set(value - step)}>
          <Minus aria-hidden="true" size={18} strokeWidth={2.4} />
        </button>
        <span className="stepper-divider" aria-hidden="true" />
        <button type="button" aria-label={t("common.increase")} disabled={value >= max} onClick={() => set(value + step)}>
          <Plus aria-hidden="true" size={18} strokeWidth={2.4} />
        </button>
      </span>
    </div>
  );
}
