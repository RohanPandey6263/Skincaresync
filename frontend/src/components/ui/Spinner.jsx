/** A rotating square outline: mechanical, not organic. */
export function Spinner({ size = 16, className = "" }) {
  return (
    <svg
      className={`shrink-0 animate-spin ${className}`.trim()}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
      focusable="false"
    >
      <rect x="4" y="4" width="16" height="16" stroke="currentColor" strokeOpacity="0.3" strokeWidth="3" />
      <path d="M4 4h16v8" stroke="currentColor" strokeWidth="3" />
    </svg>
  );
}
