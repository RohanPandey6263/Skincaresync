import SwiftUI

/// How a severity or result type is shown. Every finding states its verdict
/// three ways -- a word, a symbol and a surface -- so no single channel carries
/// it. Red is reserved for conflicts; cautions are hatched; synergies dotted.
struct TonePresentation: Equatable, Sendable {
    let label: String
    let symbol: String
    /// Fill or edge colour.
    let tint: Color
    /// Text colour when the tone is written on the page.
    let text: Color
    /// Text colour when written on the tint.
    let onTint: Color
    /// Pattern for the surface, if any.
    let pattern: Pattern?
}

extension Severity {
    var presentation: TonePresentation {
        switch self {
        case .high:
            TonePresentation(label: "High severity", symbol: "exclamationmark.octagon.fill",
                             tint: Palette.accent, text: Palette.accentText, onTint: Palette.onAccent, pattern: nil)
        case .medium:
            TonePresentation(label: "Medium severity", symbol: "exclamationmark.triangle.fill",
                             tint: Palette.ink, text: Palette.ink, onTint: Palette.onInk, pattern: .diagonal)
        case .low:
            TonePresentation(label: "Low severity", symbol: "info.circle.fill",
                             tint: Palette.ink, text: Palette.ink, onTint: Palette.onInk, pattern: .diagonal)
        }
    }

    var shortLabel: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

extension InteractionType {
    /// Presentation for the badge on a single finding.
    func presentation(severity: Severity) -> TonePresentation {
        switch self {
        case .synergy:
            TonePresentation(label: "Synergy", symbol: "sparkle",
                             tint: Palette.mint, text: Palette.ink, onTint: Palette.ink, pattern: .dots)
        case .conflict:
            TonePresentation(label: "Conflict · \(severity.shortLabel)", symbol: "exclamationmark.octagon.fill",
                             tint: Palette.accent, text: Palette.accentText, onTint: Palette.onAccent, pattern: nil)
        case .redundant:
            TonePresentation(label: "Redundant · \(severity.shortLabel)", symbol: severity.presentation.symbol,
                             tint: Palette.ink, text: Palette.ink, onTint: Palette.onInk, pattern: .diagonal)
        case .caution, .unknown:
            TonePresentation(label: "Caution · \(severity.shortLabel)", symbol: "exclamationmark.triangle.fill",
                             tint: Palette.ink, text: Palette.ink, onTint: Palette.onInk, pattern: .diagonal)
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
            TonePresentation(label: "Conflicts", symbol: "exclamationmark.octagon.fill",
                             tint: Palette.accent, text: Palette.accentText, onTint: Palette.onAccent, pattern: nil)
        case .cautions:
            TonePresentation(label: "Cautions", symbol: "exclamationmark.triangle.fill",
                             tint: Palette.ink, text: Palette.ink, onTint: Palette.onInk, pattern: .diagonal)
        case .synergies:
            TonePresentation(label: "Synergies", symbol: "sparkle",
                             tint: Palette.mint, text: Palette.ink, onTint: Palette.ink, pattern: .dots)
        }
    }

    var number: String {
        switch self {
        case .conflicts: "01"
        case .cautions: "02"
        case .synergies: "03"
        }
    }
}

extension ScoreStatus {
    var presentation: TonePresentation {
        switch self {
        case .conflict: ReportSectionKind.conflicts.presentation
        case .caution: ReportSectionKind.cautions.presentation
        case .clean:
            TonePresentation(label: "No conflicts found", symbol: "checkmark.square.fill",
                             tint: Palette.ink, text: Palette.ink, onTint: Palette.onInk, pattern: .dots)
        }
    }
}
