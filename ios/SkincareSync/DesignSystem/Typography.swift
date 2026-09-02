import SwiftUI

/// Type scale on Helvetica Neue, the grotesque the Swiss style was set in and
/// a system font on iOS. Every style is relative to a text style so Dynamic
/// Type scales it. Headings are set uppercase by the views that use them.
enum Typography {
    private static let regular = "HelveticaNeue"
    private static let medium = "HelveticaNeue-Medium"
    private static let bold = "HelveticaNeue-Bold"
    /// The heaviest cut available on iOS; used where Inter Black would be on the web.
    private static let black = "HelveticaNeue-CondensedBlack"

    /// The hero: a word made into an image.
    static let display = Font.custom(black, size: 56, relativeTo: .largeTitle)
    /// Screen titles.
    static let title = Font.custom(black, size: 36, relativeTo: .title)
    /// Group headings in the report: louder than the pair names beneath them.
    static let groupHeading = Font.custom(black, size: 40, relativeTo: .title)
    /// Sub-headings and panel titles.
    static let heading = Font.custom(bold, size: 22, relativeTo: .title2)
    /// Ingredient pair names inside a finding: deliberately smaller than the group heading.
    static let pairName = Font.custom(bold, size: 18, relativeTo: .headline)
    /// Numerals in stats and row indexes.
    static let numeral = Font.custom(black, size: 44, relativeTo: .largeTitle)
    /// Uppercase, tracked micro-labels.
    static let eyebrow = Font.custom(bold, size: 11, relativeTo: .caption)
    /// Button labels.
    static let control = Font.custom(bold, size: 13, relativeTo: .subheadline)
    static let body = Font.custom(regular, size: 17, relativeTo: .body)
    static let bodyMedium = Font.custom(medium, size: 17, relativeTo: .body)
    static let bodyBold = Font.custom(bold, size: 17, relativeTo: .body)
    static let callout = Font.custom(regular, size: 15, relativeTo: .callout)
    static let meta = Font.custom(regular, size: 13, relativeTo: .footnote)
    static let metaBold = Font.custom(bold, size: 13, relativeTo: .footnote)

    /// Tracking for uppercase micro-labels.
    static let labelTracking: CGFloat = 1.8
    /// Tracking for large uppercase headings.
    static let displayTracking: CGFloat = -1.0
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

    /// Uppercase display heading.
    func headlineStyle(_ font: Font = Typography.title, color: Color = Palette.ink) -> some View {
        self
            .font(font)
            .textCase(.uppercase)
            .kerning(Typography.displayTracking)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
