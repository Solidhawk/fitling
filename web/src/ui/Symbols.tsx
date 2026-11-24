// The filled SF Symbols the partner tab uses, drawn as SVG: lucide only has their outlines.

/** lock.fill: a solid body under its shackle. */
export function LockFill({ size = 13 }: { size?: number }) {
  return (
    <svg className="symbol" width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <path d="M7.5 10.5V7.5a4.5 4.5 0 0 1 9 0v3" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" />
      <rect x="4" y="10" width="16" height="12" rx="3" fill="currentColor" />
    </svg>
  );
}

/** checkmark.circle.fill: a solid circle with the check cut out of it. */
export function CheckCircleFill({ size = 20 }: { size?: number }) {
  return (
    <svg className="symbol" width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="12" r="11" fill="currentColor" />
      <path d="M7 12.5l3.2 3.2L17 8.8" fill="none" stroke="var(--card)" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** circle: an empty ring. */
export function Circle({ size = 20 }: { size?: number }) {
  return (
    <svg className="symbol" width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="12" r="10.2" fill="none" stroke="currentColor" strokeWidth="1.6" />
    </svg>
  );
}
