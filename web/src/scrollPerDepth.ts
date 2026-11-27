import { useEffect, useLayoutEffect, useRef } from "react";

/**
 * Where each screen of a stack was left: a screen pushed on top opens at the top, and going back returns to where the
 * screen below was, as a NavigationStack keeps it. The app does this itself (main.tsx turns the browser's own
 * restoring off): the browser would also restore the place of an entry it passes on its way back, one that leads
 * nowhere (historyStack.ts) or the welcome screen's. `depth` is that of useHistoryStack.
 */
export function useScrollPerDepth(depth: number): void {
  const positions = useRef<number[]>([]);
  const shown = useRef(depth);

  useEffect(() => {
    const remember = () => {
      positions.current[shown.current] = window.scrollY;
    };
    addEventListener("scroll", remember, { passive: true });
    return () => removeEventListener("scroll", remember);
  }, []);

  // Before the browser paints the new screen, so it never shows at the old place first. In braces: an effect may only
  // hand back its cleanup, and newer Chrome answers scrollTo with a promise.
  useLayoutEffect(() => {
    const deeper = depth > shown.current;
    shown.current = depth;
    // A new screen: what was kept for this depth and deeper belonged to screens left before (review of PR #62).
    if (deeper) positions.current = [...positions.current.slice(0, depth), 0];
    window.scrollTo(0, positions.current[depth] ?? 0);
  }, [depth]);
}
