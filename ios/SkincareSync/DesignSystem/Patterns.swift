import SwiftUI
import UIKit

/// Textures drawn with Canvas. They give a surface a second, non-colour channel
/// -- hatched means caution, dotted means synergy -- and are only ever placed on
/// a light surface, never on ink or coral. They are always clipped to the
/// rounded shape they sit inside.
enum Pattern {
    case grid, dots, diagonal
}

struct PatternView: View {
    let pattern: Pattern
    var opacity: Double = 1

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let ink = Color.primary
            switch pattern {
            case .grid:
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += Metrics.gridCell
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += Metrics.gridCell
                }
                context.stroke(path, with: .color(ink.opacity(0.05)), lineWidth: 1)
            case .dots:
                var path = Path()
                var y: CGFloat = Metrics.dotSpacing / 2
                while y <= size.height {
                    var x: CGFloat = Metrics.dotSpacing / 2
                    while x <= size.width {
                        path.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                        x += Metrics.dotSpacing
                    }
                    y += Metrics.dotSpacing
                }
                context.fill(path, with: .color(ink.opacity(0.12)))
            case .diagonal:
                var path = Path()
                let span = size.width + size.height
                var offset: CGFloat = -size.height
                while offset <= span {
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                    offset += 10
                }
                context.stroke(path, with: .color(ink.opacity(0.06)), lineWidth: 1)
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Sand surface with a grid pattern, on the card corner.
    func swissGrid(radius: CGFloat = Radius.tile) -> some View {
        patterned(.grid, base: Palette.muted, radius: radius)
    }

    /// Surface with a dot matrix: the positive channel.
    func swissDots(on base: Color = Palette.muted, radius: CGFloat = Radius.tile) -> some View {
        patterned(.dots, base: base, radius: radius)
    }

    /// Surface with diagonal hatching: the caution channel.
    func swissDiagonal(on base: Color = Palette.surface, radius: CGFloat = Radius.tile) -> some View {
        patterned(.diagonal, base: base, radius: radius)
    }

    private func patterned(_ pattern: Pattern, base: Color, radius: CGFloat) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(base)
                .overlay(PatternView(pattern: pattern).softClip(radius: radius))
        }
    }
}

/// Paper grain over the whole window at 1.5%: a tiled noise image generated once.
struct NoiseOverlay: View {
    private static let tile: UIImage = {
        let size = 96
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        var generator = SystemRandomNumberGenerator()
        return renderer.image { context in
            for y in 0..<size {
                for x in 0..<size {
                    let value = CGFloat(Int.random(in: 0...255, using: &generator)) / 255
                    context.cgContext.setFillColor(UIColor(white: value, alpha: 1).cgColor)
                    context.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()

    var body: some View {
        Image(uiImage: Self.tile)
            .resizable(resizingMode: .tile)
            .opacity(0.015)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea()
    }
}
