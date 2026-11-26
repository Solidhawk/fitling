import { useEffect, useRef } from "react";

let stacks = 0;

/**
 * Pushed screens as entries in the browser's history, so the back button and swiping back on an iPhone go one
 * screen back, as in a NavigationStack (spec: "terugknop en terugvegen"). `depth` is how many screens lie on top
 * of the first; `popTo` shows the screen at a smaller depth. The back button in the app returns `back`, so both
 * ways go through the browser's history.
 */
export function useHistoryStack(depth: number, popTo: (depth: number) => void): () => void {
  const id = useRef(0);
  if (id.current === 0) id.current = ++stacks;
  const recorded = useRef(0);
  const shown = useRef(popTo);
  shown.current = popTo;

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
      const state = event.state as { fitlingStack?: number; depth?: number } | null;
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
