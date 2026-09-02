import SwiftUI
import UIKit

/// Pastel over brown. Cream paper, sand and tan surfaces, cocoa for emphasis,
/// a warm near-black for structure, and two pastels that carry meaning: coral
/// is the signal, mint is the positive. Coral fills always carry ink text; the
/// deep coral step is the only red type.
///
/// Dark appearance keeps the same hue families on a warm black ground.
enum Palette {
    /// The canvas: warm cream.
    static let page = dynamic(light: 0xFBF7F1, dark: 0x1B1512)
    /// Text, borders, primary fills: warm near-black.
    static let ink = dynamic(light: 0x221A15, dark: 0xF3ECE3)
    /// Sand: muted surfaces that give the page rhythm.
    static let muted = dynamic(light: 0xF0E5D6, dark: 0x2A211B)
    /// Tan: a deeper step for hairlines inside muted surfaces.
    static let mutedDeep = dynamic(light: 0xD9C3AB, dark: 0x3A2F27)
    /// Cocoa: numbering, secondary emphasis and the top tab strip. 9.3:1 on paper.
    static let cocoa = dynamic(light: 0x5C3D2E, dark: 0xC9A98E)
    /// Coral: the pastel signal for fills, edges and badges.
    static let accent = dynamic(light: 0xF2A197, dark: 0xE0857A)
    /// The signal as type: 5.6:1 on paper.
    static let accentText = dynamic(light: 0xB6483C, dark: 0xF2A197)
    /// Mint: the pastel positive, for synergy surfaces.
    static let mint = dynamic(light: 0xC3E4D4, dark: 0x2F4A40)
    /// Text on an ink-filled control.
    static let onInk = dynamic(light: 0xFBF7F1, dark: 0x1B1512)
    /// Text on a coral-filled control: ink, never paper.
    static let onAccent = dynamic(light: 0x221A15, dark: 0x1B1512)
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
