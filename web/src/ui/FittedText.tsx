import { type CSSProperties, useLayoutEffect, useRef } from "react";

/** The root size from which the text counts as very large: the accessibility sizes on iOS start about there. */
const largeText = 24;

/**
 * One line of text that shrinks to at most `minimumScale` of its size before it is cut off, as
 * `.lineLimit(1).minimumScaleFactor(…)` on iOS. The class sets the size through `--fit`. With `twoLinesWhenLarge`
 * the text may take a second line at very large text, as `lineLimit(isAccessibilitySize ? 2 : 1)`.
 */
export function FittedText({
  text,
  minimumScale,
  className,
  style,
  twoLinesWhenLarge = false,
}: {
  text: string;
  minimumScale: number;
  className: string;
  style?: CSSProperties;
  twoLinesWhenLarge?: boolean;
}) {
  const ref = useRef<HTMLSpanElement>(null);

  useLayoutEffect(() => {
    const element = ref.current;
    if (!element?.parentElement) return;
    // Measured at full size each time, so a wider tile lets the text grow back.
    const fit = () => {
      element.style.setProperty("--fit", "1");
      const large = twoLinesWhenLarge && parseFloat(getComputedStyle(document.documentElement).fontSize) >= largeText;
      element.toggleAttribute("data-two-lines", large);
      if (large) return;
      const overflow = element.scrollWidth / element.clientWidth;
      if (overflow > 1) element.style.setProperty("--fit", String(Math.max(1 / overflow, minimumScale)));
    };
    fit();
    const observer = new ResizeObserver(fit);
    observer.observe(element.parentElement);
    return () => observer.disconnect();
  }, [text, minimumScale, twoLinesWhenLarge]);

  return (
    <span ref={ref} className={className} style={style}>
      {text}
    </span>
  );
}
