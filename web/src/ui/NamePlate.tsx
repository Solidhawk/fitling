/** A rounded name plate: heavy lettering on a ribbon colour, edged in white like a sticker (NamePlate.swift). */
export function NamePlate({ text, ribbon, edge = true }: { text: string; ribbon: string; edge?: boolean }) {
  return (
    <span className={edge ? "name-plate name-plate-edge" : "name-plate"} style={{ backgroundColor: ribbon }}>
      {text}
    </span>
  );
}
