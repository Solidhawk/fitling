import { language } from "../i18n";

/**
 * A line through values over days, in ink, as a LineMark with PointMarks on iOS: the value axis on the right with its
 * unit, the first and the last day below. Hidden from screen readers; the label says what it shows.
 */
export function LineChart({
  points,
  unit,
  label,
  height = 200,
  showsPoints = true,
  includesZero = true,
}: {
  points: { day: string; value: number }[];
  unit: string;
  label: string;
  height?: number;
  showsPoints?: boolean;
  /** False for body measurements: the scale starts near the values (chartYScale .automatic(includesZero: false)). */
  includesZero?: boolean;
}) {
  const width = 320;
  const pad = { left: 6, right: 44, top: 10, bottom: 22 };
  const time = (day: string) => Date.parse(`${day}T12:00:00`);
  const days = points.map((point) => time(point.day));
  const values = points.map((point) => point.value);
  const first = Math.min(...days);
  const last = Math.max(...days);
  let low = includesZero ? 0 : Math.min(...values);
  let high = Math.max(...values);
  if (high === low) {
    high += 1;
    low = includesZero ? 0 : low - 1;
  }
  const x = (day: number) => pad.left + (last === first ? 0.5 : (day - first) / (last - first)) * (width - pad.left - pad.right);
  const y = (value: number) => pad.top + (1 - (value - low) / (high - low)) * (height - pad.top - pad.bottom);
  const number = new Intl.NumberFormat(language(), { maximumFractionDigits: 1 });
  const date = new Intl.DateTimeFormat(language(), { day: "numeric", month: "short" });
  const ticks = [low, (low + high) / 2, high];
  return (
    <figure className="line-chart" aria-label={label} role="img">
      <svg viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" aria-hidden="true">
        {ticks.map((tick) => (
          <line key={tick} className="chart-grid" x1={pad.left} x2={width - pad.right} y1={y(tick)} y2={y(tick)} />
        ))}
        <polyline className="chart-line" points={points.map((point, index) => `${x(days[index])},${y(point.value)}`).join(" ")} />
        {showsPoints && points.map((point, index) => <circle key={point.day + index} className="chart-point" cx={x(days[index])} cy={y(point.value)} r={3.5} />)}
      </svg>
      <span className="chart-axis-values" aria-hidden="true">
        {[...ticks].reverse().map((tick) => (
          <span key={tick}>{number.format(tick)}</span>
        ))}
        <span className="chart-unit">{unit}</span>
      </span>
      <span className="chart-axis-days" aria-hidden="true">
        <span>{date.format(new Date(first))}</span>
        {last !== first && <span>{date.format(new Date(last))}</span>}
      </span>
    </figure>
  );
}
