export const SKIN_TYPES = [
  { value: "normal", label: "Normal" },
  { value: "oily", label: "Oily" },
  { value: "dry", label: "Dry" },
  { value: "combination", label: "Combination" },
  { value: "sensitive", label: "Sensitive" },
];

export const CONCERNS = [
  { value: "acne", label: "Acne" },
  { value: "rosacea", label: "Rosacea" },
  { value: "hyperpigmentation", label: "Hyperpigmentation" },
  { value: "eczema", label: "Eczema" },
  { value: "anti-aging", label: "Anti-aging" },
  { value: "dehydration", label: "Dehydration" },
];

export const SEVERITY_META = {
  high: { label: "High severity", tone: "danger", icon: "alertOctagon" },
  medium: { label: "Medium severity", tone: "warn", icon: "alertTriangle" },
  low: { label: "Low severity", tone: "info", icon: "info" },
};

export const SCOPE_META = {
  direct: { label: "Layered in one routine", icon: "link" },
  cumulative: { label: "Across AM and PM", icon: "refresh" },
};

export const RESULT_GROUPS = [
  {
    key: "conflicts",
    title: "Conflicts",
    tone: "danger",
    icon: "alertOctagon",
    description: "Combinations to separate or remove.",
  },
  {
    key: "cautions",
    title: "Cautions",
    tone: "warn",
    icon: "alertTriangle",
    description: "Usable with care — watch frequency and irritation.",
  },
  {
    key: "synergies",
    title: "Synergies",
    tone: "ok",
    icon: "spark",
    description: "Pairings that work better together.",
  },
];

export const ROUTINES = {
  am: { key: "am", title: "Morning routine", icon: "sun" },
  pm: { key: "pm", title: "Evening routine", icon: "moon" },
};
