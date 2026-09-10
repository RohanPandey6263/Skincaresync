import SwiftUI

// MARK: - Buttons

/// Filled Deep Forest button for the one primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Palette.onForest)
            .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget + 6)
            .padding(.horizontal, Spacing.m)
            .background(Palette.forest.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

/// Outlined button for secondary actions that still deserve weight.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Palette.forest.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget)
            .padding(.horizontal, Spacing.m)
            .background(configuration.isPressed ? Palette.surface : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .strokeBorder(Palette.divider, lineWidth: Metrics.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

/// Terracotta-filled destructive button. Reserved for sign-out and account removal.
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget + 6)
            .padding(.horizontal, Spacing.m)
            .background(Palette.terracottaText.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    static var destructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}

// MARK: - Chips

/// A selectable pill. Selection is conveyed by fill, a checkmark and the
/// accessibility trait, never by colour alone.
struct ChipToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
            Haptics.selection()
        } label: {
            HStack(spacing: Spacing.xs) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(Typography.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(isOn ? Palette.onForest : Palette.forest)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: Metrics.touchTarget - 8)
            .background(isOn ? Palette.forest : Palette.surface)
            .overlay(
                Capsule().strokeBorder(isOn ? Palette.forest : Palette.divider, lineWidth: Metrics.hairline)
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
    }
}

/// Static informational pill (e.g. "Curated", "Restricted").
struct TagPill: View {
    let text: String
    var symbol: String? = nil
    var tone: TonePresentation? = nil

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tone?.text ?? Palette.muted)
        .padding(.horizontal, Spacing.s + 2)
        .padding(.vertical, Spacing.xs + 1)
        .background(tone?.wash ?? Palette.surface)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Layout

/// Wraps its children onto as many lines as needed, like a chip row.
struct FlowLayout: Layout {
    var spacing: CGFloat = Spacing.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placements = arrange(in: bounds.width, subviews: subviews).placements
        for (index, subview) in subviews.enumerated() {
            let point = placements[index]
            subview.place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, placements: [CGPoint]) {
        var placements: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        // Propose the full width so an oversized chip wraps its text instead of
        // overflowing the container at accessibility sizes.
        let proposal = ProposedViewSize(width: width.isFinite ? width : nil, height: nil)
        for subview in subviews {
            let size = subview.sizeThatFits(proposal)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            placements.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + lineHeight), placements)
    }
}

// MARK: - Dividers and rows

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(height: Metrics.hairline)
            .accessibilityHidden(true)
    }
}

/// Label/value pair used in metadata lists.
struct MetaRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).eyebrowStyle()
            Text(value)
                .font(monospaced ? .body.monospaced() : .body)
                .foregroundStyle(Palette.forest)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - State views

/// A row of redacted placeholders shown while a list loads for the first time.
struct SkeletonRows: View {
    var count = 5

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Placeholder ingredient name")
                Text("Loading description text").font(.footnote)
            }
            .redacted(reason: .placeholder)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.sage)
                .accessibilityHidden(true)
            Text(title)
                .font(Typography.heading)
                .foregroundStyle(Palette.forest)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.secondary)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.l)
    }
}

/// Inline, recoverable error. Chooses copy for offline, unreachable and
/// rate-limited failures and always offers a retry.
struct ErrorStateView: View {
    let error: APIError
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: error.symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.terracotta)
                .accessibilityHidden(true)
            Text(error.title)
                .font(Typography.heading)
                .foregroundStyle(Palette.forest)
                .multilineTextAlignment(.center)
            Text(error.message)
                .font(Typography.body)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.secondary)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .contain)
    }
}

/// A compact error line that sits above content that is still usable.
struct InlineNotice: View {
    enum Kind { case error, info, success }

    let kind: Kind
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.meta)
                .foregroundStyle(Palette.forest)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Typography.meta.weight(.semibold))
                    .foregroundStyle(Palette.terracottaText)
                    .frame(minHeight: Metrics.touchTarget - 12)
            }
        }
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Spacing.m)
        .background(wash)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch kind {
        case .error: "exclamationmark.circle.fill"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .error: Palette.terracotta
        case .info: Palette.sage
        case .success: Palette.sage
        }
    }

    private var wash: Color {
        switch kind {
        case .error: Palette.terracottaWash
        case .info: Palette.surface
        case .success: Palette.sageWash
        }
    }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
