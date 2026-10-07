import SwiftUI

/// Type scale on Helvetica Neue, a grotesque that ships with iOS. Headings are
/// set in the bold cut at sentence case with tight tracking — big, plain and
/// quiet — while the only uppercase left is the small tracked label that names
/// a group. Every style is relative to a text style so Dynamic Type scales it.
enum Typography {
    private static let regular = "HelveticaNeue"
    private static let medium = "HelveticaNeue-Medium"
    private static let bold = "HelveticaNeue-Bold"

    /// The hero: the one line a screen opens with.
    static let display = Font.custom(bold, size: 34, relativeTo: .largeTitle)
    /// Screen titles.
    static let title = Font.custom(bold, size: 30, relativeTo: .title)
    /// Group headings in the report: louder than the pair names beneath them.
    static let groupHeading = Font.custom(bold, size: 26, relativeTo: .title)
    /// Sub-headings and panel titles.
    static let heading = Font.custom(bold, size: 20, relativeTo: .title2)
    /// Ingredient pair names inside a finding: deliberately smaller than the group heading.
    static let pairName = Font.custom(bold, size: 17, relativeTo: .headline)
    /// Numerals in stats and row indexes.
    static let numeral = Font.custom(bold, size: 32, relativeTo: .largeTitle)
    /// Uppercase, tracked micro-labels: the one place capitals survive.
    static let eyebrow = Font.custom(bold, size: 11, relativeTo: .caption)
    /// Button and chip labels, set at sentence case.
    static let control = Font.custom(bold, size: 15, relativeTo: .subheadline)
    static let body = Font.custom(regular, size: 17, relativeTo: .body)
    static let bodyMedium = Font.custom(medium, size: 17, relativeTo: .body)
    static let bodyBold = Font.custom(bold, size: 17, relativeTo: .body)
    static let callout = Font.custom(regular, size: 15, relativeTo: .callout)
    static let meta = Font.custom(regular, size: 13, relativeTo: .footnote)
    static let metaBold = Font.custom(bold, size: 13, relativeTo: .footnote)

    /// Tracking for uppercase micro-labels.
    static let labelTracking: CGFloat = 1.2
    /// Tracking for large headings: tight, the way a bold grotesque wants to sit.
    static let displayTracking: CGFloat = -0.6
}

extension View {
    /// Uppercase, tracked eyebrow label.
    func eyebrowStyle(color: Color = Palette.faint) -> some View {
        self
            .font(Typography.eyebrow)
            .textCase(.uppercase)
            .kerning(Typography.labelTracking)
            .foregroundStyle(color)
    }

    /// A heading: bold, sentence case, tightly tracked.
    func headlineStyle(_ font: Font = Typography.title, color: Color = Palette.ink) -> some View {
        self
            .font(font)
            .kerning(Typography.displayTracking)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The label on a pill control: bold, sentence case, no tracking.
    func controlLabelStyle(color: Color = Palette.ink) -> some View {
        self
            .font(Typography.control)
            .foregroundStyle(color)
    }
}
