import { Panel } from "./ui/Panel.jsx";
import { Badge } from "./ui/Badge.jsx";
import { Button } from "./ui/Button.jsx";
import { EmptyState, Skeleton } from "./ui/Feedback.jsx";
import { formatRelativeDate, sentenceCase } from "../lib/format.js";

const GAP_STATUS = {
  pending_review: { label: "Pending review", tone: "warn" },
  in_research: { label: "In research", tone: "info" },
  verified: { label: "Verified", tone: "ok" },
  published: { label: "Published", tone: "ok" },
  insufficient_evidence: { label: "Insufficient evidence", tone: "neutral" },
};

function gapStatus(status) {
  return GAP_STATUS[status] ?? { label: sentenceCase(String(status ?? "").replace(/_/g, " ")), tone: "neutral" };
}

const TH = "border-b-4 border-ink px-4 py-3 text-left font-sans text-2xs label-caps text-ink first:pl-0 last:pr-0";
const TD = "border-b-2 border-ink px-4 py-4 align-top font-sans text-sm text-ink first:pl-0 last:pr-0";

export function ResearchBacklog({ gaps, loading, onRefresh }) {
  return (
    <Panel
      number="01"
      eyebrow="Internal"
      title="Research backlog"
      description="Ingredient pairs logged during analysis that have no interaction rule yet."
      actions={
        <Button variant="secondary" icon="refresh" onClick={onRefresh} loading={loading}>
          Refresh
        </Button>
      }
    >
      {loading && !gaps.length ? (
        <div className="flex flex-col gap-4">
          {[0, 1, 2].map((row) => (
            <div key={row} className="flex items-center justify-between gap-6 border-b-2 border-ink pb-4">
              <Skeleton width="46%" height={14} />
              <Skeleton width="72px" height={14} />
            </div>
          ))}
        </div>
      ) : !gaps.length ? (
        <EmptyState
          icon="database"
          compact
          title="Backlog is empty"
          description="Unrecognised ingredient pairs are recorded here after an analysis runs."
        />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse">
            <caption className="sr-only">Ingredient pairs awaiting an interaction rule, ordered by how often they were seen</caption>
            <thead>
              <tr>
                <th scope="col" className={TH}>
                  Ingredient pair
                </th>
                <th scope="col" className={`${TH} text-right`}>
                  Hits
                </th>
                <th scope="col" className={TH}>
                  Status
                </th>
                <th scope="col" className={TH}>
                  Last seen
                </th>
              </tr>
            </thead>
            <tbody>
              {gaps.map((gap) => (
                <tr key={gap.interaction_gap_id} className="transition-colors duration-150 hover:bg-sand">
                  <th scope="row" className={`${TD} font-black uppercase tracking-tight`}>
                    {gap.ingredient_a}
                    <span className="px-2 text-coral-deep" aria-hidden="true">
                      +
                    </span>
                    <span className="sr-only">with</span>
                    {gap.ingredient_b}
                  </th>
                  <td className={`${TD} text-right font-mono`}>{gap.query_count}</td>
                  <td className={TD}>
                    <Badge size="sm" tone={gapStatus(gap.status).tone}>
                      {gapStatus(gap.status).label}
                    </Badge>
                  </td>
                  <td className={`${TD} text-ink/60`}>{formatRelativeDate(gap.last_seen) || "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Panel>
  );
}
