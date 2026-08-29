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
  return (
    GAP_STATUS[status] ?? { label: sentenceCase(String(status ?? "").replace(/_/g, " ")), tone: "neutral" }
  );
}

export function ResearchBacklog({ gaps, loading, onRefresh }) {
  return (
    <Panel
      title="Research backlog"
      icon="database"
      eyebrow="Internal"
      description="Ingredient pairs logged during analysis that have no interaction rule yet."
      actions={
        <Button variant="quiet" icon="refresh" onClick={onRefresh} loading={loading}>
          Refresh
        </Button>
      }
      className="backlogPanel"
    >
      {loading && !gaps.length ? (
        <div className="backlogSkeleton">
          {[0, 1, 2].map((row) => (
            <div key={row} className="backlogSkeleton__row">
              <Skeleton width="46%" height={13} />
              <Skeleton width="72px" height={13} />
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
        <div className="tableWrap">
          <table className="table">
            <caption className="visuallyHidden">
              Ingredient pairs awaiting an interaction rule, ordered by how often they were seen
            </caption>
            <thead>
              <tr>
                <th scope="col">Ingredient pair</th>
                <th scope="col" className="table__numeric">
                  Hits
                </th>
                <th scope="col">Status</th>
                <th scope="col">Last seen</th>
              </tr>
            </thead>
            <tbody>
              {gaps.map((gap) => (
                <tr key={gap.interaction_gap_id}>
                  <th scope="row">
                    <span className="table__pair">
                      {gap.ingredient_a}
                      <span aria-hidden="true"> + </span>
                      {gap.ingredient_b}
                    </span>
                  </th>
                  <td className="table__numeric mono">{gap.query_count}</td>
                  <td>
                    <Badge size="sm" tone={gapStatus(gap.status).tone}>
                      {gapStatus(gap.status).label}
                    </Badge>
                  </td>
                  <td className="table__muted">{formatRelativeDate(gap.last_seen) || "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Panel>
  );
}
