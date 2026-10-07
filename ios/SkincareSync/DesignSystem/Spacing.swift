import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

/// Corner radii. Everything is rounded now: the card is the unit of layout and
/// its corner is generous, controls are pills, and small chrome is a circle.
enum Radius {
    /// The big card that holds a section.
    static let card: CGFloat = 28
    /// A row or tile nested inside a card.
    static let tile: CGFloat = 20
    /// Text fields and text editors.
    static let field: CGFloat = 16
    /// Small chrome: swatches, thumbnails, wells.
    static let small: CGFloat = 12
    /// Pills and circles are drawn with `Capsule()` / `Circle()`.
    static let pill: CGFloat = 999
}

enum Metrics {
    /// Apple's minimum comfortable touch target.
    static let touchTarget: CGFloat = 44
    /// Height of a full-width pill button.
    static let controlHeight: CGFloat = 56
    /// A circular icon button.
    static let iconButton: CGFloat = 44
    /// Every stroke is a hairline; weight comes from surface, not from ink.
    static let border: CGFloat = 1
    static let hairline: CGFloat = 1
    /// Grid pattern cell.
    static let gridCell: CGFloat = 24
    /// Dot matrix spacing.
    static let dotSpacing: CGFloat = 16
}
