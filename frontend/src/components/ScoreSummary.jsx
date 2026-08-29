import { Icon } from "./ui/Icon.jsx";
import { pluralize } from "../lib/format.js";

const STATUS_META = {
  conflict: {
    tone: "danger",
    icon: "alertOctagon",
    title: "Conflicts detected",
  },
  caution: {
    tone: "warn",
    icon: "alertTriangle",
    title: "Use with care",
  },
  clean: {
    tone: "ok",
    icon: "checkCircle",
    title: "No conflicts detected",
  },
};

function summaryText(result) {
  const { overall_score: score } = result;
  if (score.status === "conflict") {
    const parts = [];
    if (score.high) parts.push(pluralize(score.high, "high-severity conflict"));
    if (score.medium) parts.push(pluralize(score.medium, "medium-severity conflict"));
    // Conflicts can all be low severity, in which case neither count applies.
    if (!parts.length) parts.push(pluralize(result.conflicts.length, "conflict"));
    return `${parts.join(" and ")} in this routine.`;
  }
  if (score.status === "caution") {
    return `${pluralize(score.count, "pairing")} to monitor, no direct conflicts.`;
  }
  return "No conflicting or cautioned pairings were found across your routines.";
}

export function ScoreSummary({ result }) {
  const meta = STATUS_META[result.overall_score.status] ?? STATUS_META.clean;

  const stats = [
    { label: "Conflicts", value: result.conflicts.length },
    { label: "Cautions", value: result.cautions.length },
    { label: "Synergies", value: result.synergies.length },
  ];

  return (
    <div className={`scoreSummary scoreSummary--${meta.tone}`}>
      <div className="scoreSummary__lead">
        <span className="scoreSummary__icon" aria-hidden="true">
          <Icon name={meta.icon} size={20} />
        </span>
        <div>
          <p className="scoreSummary__title">{meta.title}</p>
          <p className="scoreSummary__text">{summaryText(result)}</p>
        </div>
      </div>
      <dl className="scoreSummary__stats">
        {stats.map((stat) => (
          <div key={stat.label}>
            <dt>{stat.label}</dt>
            <dd>{stat.value}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
