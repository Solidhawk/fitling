import { type MouseEvent, type PointerEvent, type ReactNode, useRef, useState } from "react";

/** A button that a swipe uncovers, as a .swipeActions Button with its tint on iOS. */
export interface SwipeAction {
  label: string;
  icon?: ReactNode;
  tone: "sprout" | "ink" | "pebble";
  onSelect: () => void;
  testID?: string;
}

/** How long a finger rests on a row before its menu opens, as a long press on iOS. */
const longPress = 500;

/**
 * A list row with buttons a swipe uncovers: Delete when swiped to the left (.onDelete on iOS), or the row's own
 * actions at either edge (.swipeActions). The buttons come after the row for the keyboard and screen readers, and
 * slide into view when they have the focus. `onMenu` opens the row's menu on a long press or a right click, as
 * .contextMenu. `bare` leaves the row's padding to the child, a button that fills the row. `name` says what the row
 * is in its buttons' own names: a screen reader hears "Verwijderen, Appel", not the same word for every row (also
 * with VoiceOver's hints off, which a description would need).
 */
export function SwipeRow({
  children,
  name,
  deleteLabel,
  onDelete,
  leading = [],
  trailing = [],
  onMenu,
  bare = false,
}: {
  children: ReactNode;
  name?: string;
  deleteLabel?: string;
  onDelete?: () => void;
  leading?: SwipeAction[];
  trailing?: SwipeAction[];
  onMenu?: () => void;
  bare?: boolean;
}) {
  const [offset, setOffset] = useState(0);
  const named = name ? <span className="visually-hidden">{`, ${name}`}</span> : null;
  const start = useRef<{ x: number; y: number; offset: number; horizontal?: boolean } | null>(null);
  const leadingGroup = useRef<HTMLDivElement>(null);
  const trailingGroup = useRef<HTMLDivElement>(null);
  const timer = useRef<number>(undefined);
  // What the press that just ended did, so the click it causes does not also open the row.
  const handled = useRef(false);

  const widths = () => ({ left: leadingGroup.current?.offsetWidth ?? 0, right: trailingGroup.current?.offsetWidth ?? 0 });

  function down(event: PointerEvent) {
    start.current = { x: event.clientX, y: event.clientY, offset };
    handled.current = false;
    if (onMenu && event.pointerType === "touch") {
      timer.current = window.setTimeout(() => {
        handled.current = true;
        start.current = null;
        onMenu();
      }, longPress);
    }
  }

  function move(event: PointerEvent) {
    const begun = start.current;
    if (!begun) return;
    const dx = event.clientX - begun.x;
    const dy = event.clientY - begun.y;
    if (Math.abs(dx) > 8 || Math.abs(dy) > 8) window.clearTimeout(timer.current);
    // A swipe that starts mostly up or down is the list scrolling, not this row.
    if (begun.horizontal === undefined && Math.abs(dx) > 8) {
      begun.horizontal = Math.abs(dx) > Math.abs(dy);
      // Once it is a swipe, the row keeps getting the moves while the finger or mouse slides past its edge. Not
      // before: a tap whose pointer is captured is clicked on the row, not on the button in it (Chrome).
      if (begun.horizontal) event.currentTarget.setPointerCapture?.(event.pointerId);
    }
    if (!begun.horizontal) return;
    handled.current = true;
    const { left, right } = widths();
    setOffset(Math.min(left, Math.max(-right, begun.offset + dx)));
  }

  function up() {
    window.clearTimeout(timer.current);
    if (start.current?.horizontal) {
      const { left, right } = widths();
      setOffset((current) => (current > left / 2 ? left : current < -right / 2 ? -right : 0));
    }
    start.current = null;
  }

  // A tap on a row that is open closes it, as on iOS; a swipe or a long press is no tap. A click from the keyboard
  // (no pointer, detail 0) always goes through.
  function click(event: MouseEvent) {
    if (event.detail === 0) {
      handled.current = false;
      return;
    }
    if (!handled.current && offset === 0) return;
    event.preventDefault();
    event.stopPropagation();
    if (!handled.current) setOffset(0);
    handled.current = false;
  }

  const actions = (group: SwipeAction[], side: "leading" | "trailing") =>
    group.map((action) => (
      <button
        key={action.label}
        type="button"
        className={`swipe-action swipe-${action.tone}`}
        data-testid={action.testID}
        onFocus={() => setOffset(side === "leading" ? widths().left : -widths().right)}
        onBlur={() => setOffset(0)}
        onClick={() => {
          setOffset(0);
          action.onSelect();
        }}
      >
        {action.icon}
        <span>{action.label}</span>
        {named}
      </button>
    ));

  return (
    <div className="swipe-row">
      <div
        className={bare ? "swipe-content" : "list-row swipe-content"}
        style={{ transform: offset ? `translateX(${offset}px)` : undefined }}
        onPointerDown={down}
        onPointerMove={move}
        onPointerUp={up}
        onPointerCancel={up}
        onClickCapture={click}
        // After a long press iOS Safari still sends a click when the finger lifts, to whatever is under it by then:
        // the menu that just opened. Cancelling the touch's end keeps that click from happening.
        onTouchEnd={(event) => {
          if (handled.current) event.preventDefault();
        }}
        onContextMenu={
          onMenu &&
          ((event) => {
            event.preventDefault();
            window.clearTimeout(timer.current);
            if (handled.current) return;
            handled.current = true;
            onMenu();
          })
        }
      >
        {children}
      </div>
      {leading.length > 0 && (
        <div ref={leadingGroup} className="swipe-actions swipe-actions-leading">
          {actions(leading, "leading")}
        </div>
      )}
      {(trailing.length > 0 || (deleteLabel && onDelete)) && (
        <div ref={trailingGroup} className="swipe-actions swipe-actions-trailing">
          {actions(trailing, "trailing")}
          {deleteLabel && onDelete && (
            <button
              type="button"
              className="swipe-action swipe-delete"
              onFocus={() => setOffset(-widths().right)}
              onBlur={() => setOffset(0)}
              onClick={onDelete}
            >
              {deleteLabel}
              {named}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
