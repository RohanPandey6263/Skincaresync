import Foundation

enum ReportSectionKind: CaseIterable, Equatable, Sendable {
    case conflicts, cautions, synergies

    var title: String {
        switch self {
        case .conflicts: "Conflicts"
        case .cautions: "Cautions"
        case .synergies: "Synergies"
        }
    }

    var blurb: String {
        switch self {
        case .conflicts: "Combinations to separate or remove."
        case .cautions: "Usable with care. Watch frequency and irritation."
        case .synergies: "Pairings that work better together."
        }
    }

    var emptyText: String {
        switch self {
        case .conflicts: "No conflicts between these products."
        case .cautions: "No cautions for these products."
        case .synergies: "No known synergies between these products."
        }
    }
}

struct ReportSection: Identifiable, Equatable, Sendable {
    let kind: ReportSectionKind
    let findings: [InteractionFinding]

    var id: ReportSectionKind { kind }
    var count: Int { findings.count }
}

/// Pure view-model for the report: grouping, ordering and copy. No SwiftUI.
struct ReportPresentation: Equatable, Sendable {
    let status: ScoreStatus
    let summaryTitle: String
    let countsLine: String
    let sections: [ReportSection]
    let unknownPairCount: Int
    let unresolvedTokens: [UnresolvedToken]
    let parsedProducts: [ParsedProduct]

    static let disclaimer = "This is ingredient-compatibility information drawn from published studies. It is not a diagnosis or medical advice. Patch-test new products and talk to a dermatologist about persistent irritation."

    init(result: AnalysisResult) {
        status = result.overallScore.status
        summaryTitle = Self.summaryTitle(for: result.overallScore)
        countsLine = Self.countsLine(conflicts: result.conflicts.count, cautions: result.cautions.count, synergies: result.synergies.count)
        // Safety order, always all three so the reader sees an explicit "none".
        sections = [
            ReportSection(kind: .conflicts, findings: Self.sortedBySeverity(result.conflicts)),
            ReportSection(kind: .cautions, findings: Self.sortedBySeverity(result.cautions)),
            ReportSection(kind: .synergies, findings: result.synergies),
        ]
        unknownPairCount = result.unknownPairCount
        unresolvedTokens = result.unresolvedTokens
        parsedProducts = result.parsedProducts
    }

    static func summaryTitle(for score: OverallScore) -> String {
        switch score.status {
        case .conflict: "Conflicts detected"
        case .caution: "Use with care"
        case .clean: "No conflicts found"
        }
    }

    static func countsLine(conflicts: Int, cautions: Int, synergies: Int) -> String {
        func word(_ count: Int, _ singular: String, _ plural: String) -> String {
            "\(count) \(count == 1 ? singular : plural)"
        }
        return [
            word(conflicts, "conflict", "conflicts"),
            word(cautions, "caution", "cautions"),
            word(synergies, "synergy", "synergies"),
        ].joined(separator: " · ")
    }

    /// Stable sort: highest severity first, original order within a level.
    static func sortedBySeverity(_ findings: [InteractionFinding]) -> [InteractionFinding] {
        findings.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.severity != rhs.element.severity { return lhs.element.severity > rhs.element.severity }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Copy for the escalation notice on one finding, or nil when none applied.
    static func escalationText(for finding: InteractionFinding, profile: SkinProfile) -> String? {
        guard finding.wasEscalated else { return nil }
        let concerns = profile.concerns.map { $0.label.lowercased() }
        let reason = concerns.isEmpty
            ? "for \(profile.skinType.label.lowercased()) skin"
            : "for \(profile.skinType.label.lowercased()) skin and your concerns (\(concerns.joined(separator: ", ")))"
        return "Raised from \(finding.baseSeverity.rawValue) to \(finding.severity.rawValue) \(reason)."
    }

    /// "Provisional" -> "Provisional evidence".
    static func confidenceLabel(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.prefix(1).uppercased() + value.dropFirst()
    }
}
