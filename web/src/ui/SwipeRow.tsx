import { type PointerEvent, type ReactNode, useRef, useState } from "react";

/** How far the row slides open: the width of the delete button. */
const opened = 96;

/**
 * A list row that shows Delete when swiped to the left, as .onDelete in a List on iOS. The button comes after the row
 * for the keyboard and screen readers, and slides into view when it has the focus.
 */
export function SwipeRow({ children, deleteLabel, onDelete }: { children: ReactNode; deleteLabel: string; onDelete: () => void }) {
  const [offset, setOffset] = useState(0);
  const start = useRef<{ x: number; y: number; offset: number; horizontal?: boolean } | null>(null);

  function down(event: PointerEvent) {
    start.current = { x: event.clientX, y: event.clientY, offset };
    // The row keeps getting the moves while the finger or mouse slides past its edge.
    event.currentTarget.setPointerCapture?.(event.pointerId);
  }

  function move(event: PointerEvent) {
    const begun = start.current;
    if (!begun) return;
    const dx = event.clientX - begun.x;
    const dy = event.clientY - begun.y;
    // A swipe that starts mostly up or down is the list scrolling, not this row.
    begun.horizontal ??= Math.abs(dx) > 8 ? Math.abs(dx) > Math.abs(dy) : undefined;
    if (!begun.horizontal) return;
    setOffset(Math.min(0, Math.max(-opened, begun.offset + dx)));
  }

  function up() {
    if (start.current?.horizontal) setOffset((current) => (current < -opened / 2 ? -opened : 0));
    start.current = null;
  }

  return (
    <div className="swipe-row">
      <div
        className="list-row swipe-content"
        style={{ transform: offset ? `translateX(${offset}px)` : undefined }}
        onPointerDown={down}
        onPointerMove={move}
        onPointerUp={up}
        onPointerCancel={up}
      >
        {children}
      </div>
      <button
        type="button"
        className="swipe-delete"
        onFocus={() => setOffset(-opened)}
        onBlur={() => setOffset(0)}
        onClick={onDelete}
      >
        {deleteLabel}
      </button>
    </div>
  );
}
