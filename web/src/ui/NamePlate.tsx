/**
 * A rounded name plate: heavy lettering on a ribbon colour, edged in white like a sticker (NamePlate.swift).
 * `ink` for a plate on a pale fill such as Track, where the lettering is ink.
 */
export function NamePlate({ text, ribbon, edge = true, ink = false }: { text: string; ribbon: string; edge?: boolean; ink?: boolean }) {
  return (
    <span className={edge ? "name-plate name-plate-edge" : "name-plate"} style={{ backgroundColor: ribbon, color: ink ? "var(--ink)" : undefined }}>
      {text}
    </span>
  );
}
