import SwiftUI
import UIKit

/// The botanical palette. Every colour in the app comes from here so the light
/// and dark variants stay in step and contrast is decided in one place.
///
/// Light values are the brand hexes from the brief; dark values keep the same
/// hue family at a lightness that clears WCAG AA against the dark page.
enum Palette {
    /// Warm Alabaster page background.
    static let page = dynamic(light: 0xF9F8F4, dark: 0x151915)
    /// Linen: grouped surfaces, sheets, list backgrounds.
    static let surface = dynamic(light: 0xF2F0EB, dark: 0x1E231F)
    /// A slightly lifted surface for rows inside a linen surface.
    static let surfaceRaised = dynamic(light: 0xFFFFFF, dark: 0x262C27)
    /// Stone: hairline dividers.
    static let divider = dynamic(light: 0xE6E2DA, dark: 0x30372F)
    /// Deep Forest: primary text and primary actions.
    static let forest = dynamic(light: 0x2D3A31, dark: 0xE9E7E0)
    /// Secondary text.
    static let muted = dynamic(light: 0x5B665E, dark: 0xA9B0A8)
    /// Tertiary text: eyebrows and metadata.
    static let faint = dynamic(light: 0x7A847C, dark: 0x8A928A)
    /// Sage: accent and positive signal.
    static let sage = dynamic(light: 0x8C9A84, dark: 0x9DAB95)
    /// Sage at a contrast that works as text.
    static let sageText = dynamic(light: 0x535D4D, dark: 0xB6C3AE)
    /// Sage wash for positive cards.
    static let sageWash = dynamic(light: 0xE8ECE3, dark: 0x233026)
    /// Soft Clay: cautions and warm neutral fills.
    static let clay = dynamic(light: 0xDCCFC2, dark: 0x574A3F)
    /// Clay at a contrast that works as text.
    static let clayText = dynamic(light: 0x7A5F4A, dark: 0xE0C9B4)
    /// Clay wash for caution cards.
    static let clayWash = dynamic(light: 0xF3ECE4, dark: 0x2E2822)
    /// Terracotta: conflicts and the interactive accent.
    static let terracotta = dynamic(light: 0xC27B66, dark: 0xD48F79)
    /// Terracotta at a contrast that works as text.
    static let terracottaText = dynamic(light: 0x884936, dark: 0xEBAA95)
    /// Terracotta wash for conflict cards.
    static let terracottaWash = dynamic(light: 0xF6E6E0, dark: 0x33241F)
    /// Text placed on a forest-filled control.
    static let onForest = dynamic(light: 0xF9F8F4, dark: 0x151915)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
