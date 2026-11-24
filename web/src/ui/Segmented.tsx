/** A segmented Picker: the choices side by side in one capsule, the chosen one raised (pickerStyle(.segmented)). */
export function Segmented<Value extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: Value;
  options: [Value, string][];
  onChange: (value: Value) => void;
}) {
  return (
    <span className="segmented" role="radiogroup" aria-label={label}>
      {options.map(([option, title]) => (
        <button key={option} type="button" role="radio" aria-checked={value === option} className="segment" onClick={() => onChange(option)}>
          {title}
        </button>
      ))}
    </span>
  );
}
