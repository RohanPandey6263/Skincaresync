import SwiftUI

/// How a severity or result type is shown. Every finding states its verdict
/// three ways -- a word, a symbol and a colour -- so no single channel carries it.
struct TonePresentation: Equatable, Sendable {
    let label: String
    let symbol: String
    let tint: Color
    let text: Color
    let wash: Color
}

extension Severity {
    var presentation: TonePresentation {
        switch self {
        case .high:
            TonePresentation(
                label: "High severity", symbol: "exclamationmark.octagon.fill",
                tint: Palette.terracotta, text: Palette.terracottaText, wash: Palette.terracottaWash)
        case .medium:
            TonePresentation(
                label: "Medium severity", symbol: "exclamationmark.triangle.fill",
                tint: Palette.clay, text: Palette.clayText, wash: Palette.clayWash)
        case .low:
            TonePresentation(
                label: "Low severity", symbol: "info.circle.fill",
                tint: Palette.divider, text: Palette.muted, wash: Palette.surface)
        }
    }
}

extension InteractionType {
    /// Presentation for the badge on a single finding.
    func presentation(severity: Severity) -> TonePresentation {
        switch self {
        case .synergy:
            TonePresentation(
                label: "Synergy", symbol: "leaf.fill",
                tint: Palette.sage, text: Palette.sageText, wash: Palette.sageWash)
        case .redundant:
            TonePresentation(
                label: "Redundant · \(severity.shortLabel)", symbol: severity.presentation.symbol,
                tint: severity.presentation.tint, text: severity.presentation.text, wash: severity.presentation.wash)
        case .conflict, .caution, .unknown:
            severity.presentation
        }
    }
}

extension Severity {
    var shortLabel: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

extension InteractionScope {
    var label: String {
        switch self {
        case .direct: "In one routine"
        case .cumulative: "Across AM and PM"
        }
    }

    var symbol: String {
        switch self {
        case .direct: "link"
        case .cumulative: "arrow.triangle.2.circlepath"
        }
    }

    var explanation: String {
        switch self {
        case .direct: "These products are layered in the same routine."
        case .cumulative: "One is used in the morning and the other at night; the effect builds up over the day."
        }
    }
}

extension ReportSectionKind {
    var presentation: TonePresentation {
        switch self {
        case .conflicts:
            TonePresentation(
                label: "Conflicts", symbol: "exclamationmark.octagon.fill",
                tint: Palette.terracotta, text: Palette.terracottaText, wash: Palette.terracottaWash)
        case .cautions:
            TonePresentation(
                label: "Cautions", symbol: "exclamationmark.triangle.fill",
                tint: Palette.clay, text: Palette.clayText, wash: Palette.clayWash)
        case .synergies:
            TonePresentation(
                label: "Synergies", symbol: "leaf.fill",
                tint: Palette.sage, text: Palette.sageText, wash: Palette.sageWash)
        }
    }
}

extension ScoreStatus {
    var presentation: TonePresentation {
        switch self {
        case .conflict: ReportSectionKind.conflicts.presentation
        case .caution: ReportSectionKind.cautions.presentation
        case .clean:
            TonePresentation(
                label: "No conflicts found", symbol: "checkmark.circle.fill",
                tint: Palette.sage, text: Palette.sageText, wash: Palette.sageWash)
        }
    }
}
