import SwiftUI

/// Type scale. Display text uses the system serif (New York) for the editorial
/// voice; every control and body run uses San Francisco. All styles are built
/// on text styles so Dynamic Type scales them.
enum Typography {
    /// Hero headline.
    static let display = Font.system(.largeTitle, design: .serif, weight: .medium)
    /// Screen and report section headings.
    static let title = Font.system(.title, design: .serif, weight: .medium)
    /// Sub-headings inside a screen.
    static let heading = Font.system(.title3, design: .serif, weight: .medium)
    /// Group headings that must read louder than the pair names beneath them.
    static let groupHeading = Font.system(.title2, design: .serif, weight: .semibold)
    /// Ingredient pair names inside a finding: deliberately smaller than the group heading.
    static let pairName = Font.system(.headline, design: .default, weight: .semibold)
    /// Small uppercase labels ("Ingredient interaction engine").
    static let eyebrow = Font.system(.caption, design: .default, weight: .semibold)
    /// Metadata and status lines.
    static let meta = Font.system(.footnote)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout)
}

extension View {
    /// Uppercase, tracked eyebrow label.
    func eyebrowStyle() -> some View {
        self
            .font(Typography.eyebrow)
            .textCase(.uppercase)
            .kerning(1.1)
            .foregroundStyle(Palette.faint)
    }
}
