import { ChevronsUpDown } from "lucide-react";
import { ListRow } from "./List";

/** A Picker in a Form: the label, the chosen value on the right, the choices when tapped. */
export function PickerRow<Value extends string>({
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
    <ListRow>
      <label className="labeled picker-row">
        <span>{label}</span>
        <span className="picker-value">
          <select className="picker" value={value} onChange={(event) => onChange(event.target.value as Value)}>
            {options.map(([option, title]) => (
              <option key={option} value={option}>
                {title}
              </option>
            ))}
          </select>
          <ChevronsUpDown className="picker-chevrons" aria-hidden="true" size={14} strokeWidth={2.4} />
        </span>
      </label>
    </ListRow>
  );
}
