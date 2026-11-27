import { useEffect, useRef } from "react";

// Stacks are told apart per page load: an entry from before a reload belongs to none of the stacks on screen now.
const load = Math.random().toString(36).slice(2, 10);
let stacks = 0;
/** The stacks on screen now. */
const onScreen = new Set<string>();

// An entry of a stack that is no longer on screen (a sheet that closed by itself, the screens of a tab that was left, a
// page from before a reload) leads nowhere: Back goes on past it, so one press of Back always does something
// (UNFORGET S40).
if (typeof window !== "undefined") {
  addEventListener("popstate", (event) => {
    const stack = (event.state as { fitlingStack?: unknown } | null)?.fitlingStack;
    if (stack !== undefined && !onScreen.has(String(stack))) history.back();
  });
}

/**
 * Pushed screens as entries in the browser's history, so the back button and swiping back on an iPhone go one
 * screen back, as in a NavigationStack (spec: "terugknop en terugvegen"). `depth` is how many screens lie on top
 * of the first; `popTo` shows the screen at a smaller depth. The back button in the app returns `back`, so both
 * ways go through the browser's history.
 */
export function useHistoryStack(depth: number, popTo: (depth: number) => void): () => void {
  const id = useRef("");
  if (id.current === "") id.current = `${load}-${++stacks}`;
  const recorded = useRef(0);
  const shown = useRef(popTo);
  shown.current = popTo;

  // Before the entries below are made, so an entry of this stack is never taken for one that leads nowhere.
  useEffect(() => {
    const mine = id.current;
    onScreen.add(mine);
    return () => {
      onScreen.delete(mine);
    };
  }, []);

  useEffect(() => {
    while (recorded.current < depth) {
      recorded.current += 1;
      history.pushState({ fitlingStack: id.current, depth: recorded.current }, "");
    }
    recorded.current = depth;
  }, [depth]);

  useEffect(() => {
    // An entry of another stack (an onboarding that is over) counts as this stack's first screen.
    const onPop = (event: PopStateEvent) => {
      const state = event.state as { fitlingStack?: unknown; depth?: number } | null;
      const target = state?.fitlingStack === id.current ? (state.depth ?? 0) : 0;
      if (target >= recorded.current) return;
      recorded.current = target;
      shown.current(target);
    };
    addEventListener("popstate", onPop);
    return () => removeEventListener("popstate", onPop);
  }, []);

  return () => history.back();
}
