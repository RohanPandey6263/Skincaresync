const PATHS = {
  shield: (
    <>
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
      <path d="m9 12 2 2 4-4" />
    </>
  ),
  mail: (
    <>
      <rect x="2" y="4" width="20" height="16" rx="2" />
      <path d="m2 7 10 6 10-6" />
    </>
  ),
  eye: (
    <>
      <path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z" />
      <circle cx="12" cy="12" r="3" />
    </>
  ),
  eyeOff: (
    <>
      <path d="M9.9 5.2A9.9 9.9 0 0 1 12 5c6.4 0 10 7 10 7a17.6 17.6 0 0 1-3.2 4.2M6.2 6.2A17.7 17.7 0 0 0 2 12s3.6 7 10 7a9.8 9.8 0 0 0 4.1-.9" />
      <path d="M10.6 10.6a2 2 0 0 0 2.8 2.8" />
      <path d="m3 3 18 18" />
    </>
  ),
  logOut: (
    <>
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <path d="m16 17 5-5-5-5M21 12H9" />
    </>
  ),
  sun: (
    <>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </>
  ),
  moon: <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" />,
  plus: <path d="M12 5v14M5 12h14" />,
  trash: <path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v5M14 11v5" />,
  search: (
    <>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.6-3.6" />
    </>
  ),
  camera: (
    <>
      <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h3l2-3h6l2 3h3a2 2 0 0 1 2 2z" />
      <circle cx="12" cy="13" r="3.5" />
    </>
  ),
  close: <path d="M18 6 6 18M6 6l12 12" />,
  external: <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6M15 3h6v6M10 14 21 3" />,
  chevronDown: <path d="m6 9 6 6 6-6" />,
  checkCircle: (
    <>
      <path d="M21.9 11.2V12a10 10 0 1 1-5.9-9.1" />
      <path d="m9 11 3 3 9.5-9.5" />
    </>
  ),
  alertTriangle: (
    <>
      <path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" />
      <path d="M12 9v4.5M12 17.2h.01" />
    </>
  ),
  alertOctagon: (
    <>
      <path d="M7.9 2h8.2L22 7.9v8.2L16.1 22H7.9L2 16.1V7.9z" />
      <path d="M12 8v4.5M12 16h.01" />
    </>
  ),
  link: (
    <>
      <path d="M9.2 14.8 14.8 9.2" />
      <path d="M10.6 6.6 12 5.2a4 4 0 0 1 5.7 5.7l-1.4 1.4M13.4 17.4 12 18.8a4 4 0 0 1-5.7-5.7l1.4-1.4" />
    </>
  ),
  info: (
    <>
      <circle cx="12" cy="12" r="9.5" />
      <path d="M12 16.5v-5M12 8h.01" />
    </>
  ),
  database: (
    <>
      <ellipse cx="12" cy="5.5" rx="8.5" ry="2.8" />
      <path d="M3.5 5.5v13c0 1.55 3.8 2.8 8.5 2.8s8.5-1.25 8.5-2.8v-13" />
      <path d="M3.5 12c0 1.55 3.8 2.8 8.5 2.8s8.5-1.25 8.5-2.8" />
    </>
  ),
  refresh: (
    <>
      <path d="M20.5 12a8.5 8.5 0 1 1-2.6-6.1L20.5 8" />
      <path d="M20.5 3.5v5h-5" />
    </>
  ),
  user: (
    <>
      <circle cx="12" cy="8" r="3.8" />
      <path d="M4.5 20.5a7.5 7.5 0 0 1 15 0" />
    </>
  ),
  beaker: (
    <>
      <path d="M9 3h6M10 3v5.6L4.6 18a2 2 0 0 0 1.7 3h11.4a2 2 0 0 0 1.7-3L14 8.6V3" />
      <path d="M7.2 15h9.6" />
    </>
  ),
  arrowRight: <path d="M4 12h15M13.5 6.5 20 12l-6.5 5.5" />,
  spark: <path d="M12 3.2 13.9 9l5.8 1.9-5.8 1.9L12 18.6l-1.9-5.8L4.3 10.9 10.1 9z" />,
  book: (
    <>
      <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
      <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
    </>
  ),
};

export function Icon({ name, size = 16, className = "", strokeWidth = 1.75 }) {
  const glyph = PATHS[name];
  if (!glyph) return null;

  return (
    <svg
      className={`icon ${className}`.trim()}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {glyph}
    </svg>
  );
}

export function Logomark({ size = 28 }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 32 32"
      aria-hidden="true"
      focusable="false"
      className="logomark"
    >
      <rect width="32" height="32" rx="8" fill="currentColor" />
      <path
        d="M16 6.5c3.6 4 6 7 6 10a6 6 0 0 1-12 0c0-3 2.4-6 6-10z"
        fill="var(--paper-100)"
      />
      <path
        d="M16 12.5v7"
        stroke="var(--ink-800)"
        strokeWidth="1.5"
        strokeLinecap="round"
      />
    </svg>
  );
}
