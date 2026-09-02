import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Metrics {
    /// Apple's minimum comfortable touch target.
    static let touchTarget: CGFloat = 44
    /// There is no radius. Named so the absence is deliberate, not forgotten.
    static let cornerRadius: CGFloat = 0
    /// The standard visible border.
    static let border: CGFloat = 2
    /// The heavy border that frames a section.
    static let borderHeavy: CGFloat = 4
    static let hairline: CGFloat = 1
    /// Coloured edge on a finding card.
    static let findingEdge: CGFloat = 8
    /// Grid pattern cell.
    static let gridCell: CGFloat = 24
    /// Dot matrix spacing.
    static let dotSpacing: CGFloat = 16
}
