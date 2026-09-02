import SwiftUI
import UIKit

/// The Swiss International palette. Closed by design: white, black, one gray
/// and one red. Secondary text is black at reduced alpha, never a new hue.
///
/// Dark appearance is the poster inverted: black page, white ink. Red is the
/// same signal in both.
enum Palette {
    /// The canvas. Pure white; pure black when inverted.
    static let page = dynamic(light: 0xFFFFFF, dark: 0x000000)
    /// Text, borders, primary fills.
    static let ink = dynamic(light: 0x000000, dark: 0xFFFFFF)
    /// Muted surfaces that give the page rhythm.
    static let muted = dynamic(light: 0xF2F2F2, dark: 0x161616)
    /// A second gray step for hairlines inside muted surfaces.
    static let mutedDeep = dynamic(light: 0xE0E0E0, dark: 0x2A2A2A)
    /// Swiss Red. Fills, large type and edges only; 3.7:1 on white.
    static let accent = dynamic(light: 0xFF3000, dark: 0xFF3000)
    /// The same signal at 5.7:1 for small red type on the page.
    static let accentText = dynamic(light: 0xC62400, dark: 0xFF6B47)
    /// Text on an ink-filled control.
    static let onInk = dynamic(light: 0xFFFFFF, dark: 0x000000)
    /// Text on an accent-filled control.
    static let onAccent = Color.white
    /// Secondary text: ink at 62%.
    static var secondary: Color { ink.opacity(0.62) }
    /// Tertiary text: ink at 45%.
    static var faint: Color { ink.opacity(0.45) }
    /// Structure is visible: borders are ink.
    static var border: Color { ink }

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
