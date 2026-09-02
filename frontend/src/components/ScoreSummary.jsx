import { Icon } from "./ui/Icon.jsx";
import { pluralize } from "../lib/format.js";

const STATUS_META = {
  conflict: { icon: "alertOctagon", title: "Conflicts detected", tone: "text-accent" },
  caution: { icon: "alertTriangle", title: "Use with care", tone: "text-black" },
  clean: { icon: "checkCircle", title: "No conflicts detected", tone: "text-black" },
};

function summaryText(result) {
  const { overall_score: score } = result;
  if (score.status === "conflict") {
    const parts = [];
    if (score.high) parts.push(pluralize(score.high, "high-severity conflict"));
    if (score.medium) parts.push(pluralize(score.medium, "medium-severity conflict"));
    if (!parts.length) parts.push(pluralize(result.conflicts.length, "conflict"));
    return `${parts.join(" and ")} in this routine.`;
  }
  if (score.status === "caution") {
    return `${pluralize(score.count, "pairing")} to monitor, no direct conflicts.`;
  }
  return "No conflicting or cautioned pairings were found across your routines.";
}

/**
 * 7:5. The verdict is set as large as the column allows; the three counts sit
 * in a bordered grid beside it. Red appears only when there are conflicts.
 */
export function ScoreSummary({ result }) {
  const meta = STATUS_META[result.overall_score.status] ?? STATUS_META.clean;

  const stats = [
    { label: "Conflicts", value: result.conflicts.length, accent: result.conflicts.length > 0 },
    { label: "Cautions", value: result.cautions.length, accent: false },
    { label: "Synergies", value: result.synergies.length, accent: false },
  ];

  return (
    <div className="grid grid-cols-1 border-4 border-black lg:grid-cols-12">
      <div className="flex flex-col gap-5 p-6 md:p-8 lg:col-span-7 lg:border-r-4 lg:border-black">
        <p className="flex items-center gap-3 font-sans text-2xs label-caps text-black">
          <Icon name={meta.icon} size={16} strokeWidth={2.5} className={meta.tone} />
          Verdict
        </p>
        <p className={`font-sans text-display font-black uppercase ${meta.tone}`}>{meta.title}</p>
        <p className="max-w-[48ch] font-sans text-base leading-relaxed text-black/70">{summaryText(result)}</p>
      </div>
      <dl className="grid grid-cols-3 gap-1 border-t-4 border-black bg-black lg:col-span-5 lg:border-t-0">
        {stats.map((stat) => (
          <div key={stat.label} className="flex flex-col justify-between gap-6 bg-white p-4 md:p-6">
            <dt className="font-sans text-2xs label-caps text-black/60">{stat.label}</dt>
            <dd className={`font-sans text-5xl font-black leading-none tracking-tighter md:text-7xl ${stat.accent ? "text-accent" : "text-black"}`}>
              {stat.value}
            </dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
