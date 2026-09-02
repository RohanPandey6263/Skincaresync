import SwiftUI

// MARK: - Buttons

/// Filled ink button for the one primary action on a screen. Pressing snaps
/// it to Swiss Red: an inversion, never a fade.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.control)
            .textCase(.uppercase)
            .kerning(Typography.labelTracking)
            .foregroundStyle(Palette.onInk)
            .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget + 8)
            .padding(.horizontal, Spacing.m)
            .background(configuration.isPressed ? Palette.accent : Palette.ink)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .animation(.linear(duration: 0.12), value: configuration.isPressed)
    }
}

/// Outlined button. Pressing inverts it to ink.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.control)
            .textCase(.uppercase)
            .kerning(Typography.labelTracking)
            .foregroundStyle(configuration.isPressed ? Palette.onInk : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget)
            .padding(.horizontal, Spacing.m)
            .background(configuration.isPressed ? Palette.ink : Palette.page)
            .overlay(Rectangle().strokeBorder(Palette.border, lineWidth: Metrics.border))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .animation(.linear(duration: 0.12), value: configuration.isPressed)
    }
}

/// Swiss Red fill. Reserved for sign-out and account removal: the signal colour.
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.control)
            .textCase(.uppercase)
            .kerning(Typography.labelTracking)
            .foregroundStyle(configuration.isPressed ? Palette.onInk : Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget + 8)
            .padding(.horizontal, Spacing.m)
            .background(configuration.isPressed ? Palette.ink : Palette.accent)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .animation(.linear(duration: 0.12), value: configuration.isPressed)
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

/// A selectable rectangle. Selection is a full inversion to ink plus a square
/// marker and the accessibility trait, never colour alone.
struct ChipToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
            Haptics.selection()
        } label: {
            HStack(spacing: Spacing.s) {
                Rectangle()
                    .strokeBorder(isOn ? Palette.onInk : Palette.ink, lineWidth: Metrics.border)
                    .background(isOn ? Palette.onInk : Color.clear)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Typography.control)
                    .textCase(.uppercase)
                    .kerning(Typography.labelTracking)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(isOn ? Palette.onInk : Palette.ink)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: Metrics.touchTarget)
            .background(isOn ? Palette.ink : Palette.page)
            .overlay(Rectangle().strokeBorder(Palette.border, lineWidth: Metrics.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
    }
}

/// Static informational rectangle ("Curated", "High severity").
struct TagPill: View {
    let text: String
    var symbol: String? = nil
    var tone: TonePresentation? = nil
    /// When true the tag is filled with the tone's tint instead of outlined.
    var filled = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Typography.eyebrow)
                .textCase(.uppercase)
                .kerning(Typography.labelTracking)
        }
        .foregroundStyle(filled ? (tone?.onTint ?? Palette.onInk) : (tone?.text ?? Palette.ink))
        .padding(.horizontal, Spacing.s + 2)
        .padding(.vertical, Spacing.xs + 2)
        .background(filled ? (tone?.tint ?? Palette.ink) : Palette.page)
        .overlay(Rectangle().strokeBorder(tone?.tint ?? Palette.ink, lineWidth: Metrics.border))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Structure

/// Numbered section label: "01. Profile". Red numeral, tracked uppercase word.
struct SectionLabel: View {
    let number: String?
    let title: String

    init(_ number: String? = nil, _ title: String) {
        self.number = number
        self.title = title
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let number {
                Text("\(number).")
                    .foregroundStyle(Palette.accentText)
            }
            Text(title)
                .foregroundStyle(Palette.ink)
        }
        .font(Typography.eyebrow)
        .textCase(.uppercase)
        .kerning(Typography.labelTracking)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(number.map { "Section \($0), \(title)" } ?? title)
    }
}

/// A bordered rectangle that frames a group of content, with a numbered header.
struct Panel<Content: View>: View {
    let number: String?
    let eyebrow: String?
    let title: String?
    var description: String? = nil
    var heavy = false
    @ViewBuilder let content: () -> Content

    init(number: String? = nil, eyebrow: String? = nil, title: String? = nil, description: String? = nil,
         heavy: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.number = number
        self.eyebrow = eyebrow
        self.title = title
        self.description = description
        self.heavy = heavy
        self.content = content
    }

    private var width: CGFloat { heavy ? Metrics.borderHeavy : Metrics.border }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || eyebrow != nil || number != nil {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    if number != nil || eyebrow != nil {
                        SectionLabel(number, eyebrow ?? "")
                    }
                    if let title {
                        Text(title)
                            .headlineStyle(Typography.heading)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let description {
                        Text(description)
                            .font(Typography.meta)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.m)
                Rule(width: width)
            }
            content()
        }
        .background(Palette.page)
        .overlay(Rectangle().strokeBorder(Palette.border, lineWidth: width))
    }
}

/// A horizontal rule with real weight.
struct Rule: View {
    var width: CGFloat = Metrics.border

    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: width)
            .accessibilityHidden(true)
    }
}

/// Backwards-compatible name used across the views.
typealias Hairline = Rule

/// Label/value pair used in metadata lists.
struct MetaRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).eyebrowStyle()
            Text(value)
                .font(monospaced ? Typography.body.monospaced() : Typography.body)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A list row that draws its own 2pt rule beneath, for plain lists.
struct RuledRow<Content: View>: View {
    var rule: CGFloat = Metrics.border
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            Rule(width: rule)
        }
    }
}

extension View {
    /// Removes the system separators and insets so a plain list can carry its own rules.
    func swissRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
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

// MARK: - State views

/// Redacted placeholders shown while a list loads for the first time.
struct SkeletonRows: View {
    var count = 5

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            VStack(alignment: .leading, spacing: Spacing.s) {
                Rectangle().fill(Palette.mutedDeep).frame(width: 180, height: 16)
                Rectangle().fill(Palette.mutedDeep).frame(width: 260, height: 10)
                Rule()
            }
            .padding(.top, Spacing.m)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// An icon enclosed in a bordered square.
struct IconBox: View {
    let symbol: String
    var tone: TonePresentation? = nil
    var filled = false

    var body: some View {
        Image(systemName: symbol)
            .font(.title3.weight(.bold))
            .foregroundStyle(filled ? (tone?.onTint ?? Palette.onInk) : (tone?.text ?? Palette.ink))
            .frame(width: 48, height: 48)
            .background(filled ? (tone?.tint ?? Palette.ink) : Palette.page)
            .overlay(Rectangle().strokeBorder(tone?.tint ?? Palette.ink, lineWidth: Metrics.border))
            .accessibilityHidden(true)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            IconBox(symbol: symbol)
            Text(title)
                .headlineStyle(Typography.heading)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Typography.callout)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .swissGrid()
        .overlay(Rectangle().strokeBorder(Palette.border, lineWidth: Metrics.border))
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.l)
    }
}

/// Inline, recoverable error with a red edge and a retry.
struct ErrorStateView: View {
    let error: APIError
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            IconBox(symbol: error.symbol, tone: Severity.high.presentation, filled: true)
            Text(error.title)
                .headlineStyle(Typography.heading)
                .accessibilityAddTraits(.isHeader)
            Text(error.message)
                .font(Typography.callout)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .padding(.leading, Metrics.findingEdge)
        .background(Palette.page)
        .overlay(alignment: .leading) { Rectangle().fill(Palette.accent).frame(width: Metrics.findingEdge) }
        .overlay(Rectangle().strokeBorder(Palette.border, lineWidth: Metrics.border))
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.l)
        .accessibilityElement(children: .contain)
    }
}

/// A compact notice that sits above content that is still usable.
struct InlineNotice: View {
    enum Kind { case error, info, success }

    let kind: Kind
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.meta)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Typography.eyebrow)
                    .textCase(.uppercase)
                    .kerning(Typography.labelTracking)
                    .frame(minHeight: Metrics.touchTarget - 12)
            }
        }
        .foregroundStyle(kind == .success ? Palette.onInk : Palette.ink)
        .padding(.vertical, Spacing.s + 2)
        .padding(.horizontal, Spacing.m)
        .padding(.leading, Metrics.findingEdge)
        .background(surface)
        .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: Metrics.findingEdge) }
        .overlay(Rectangle().strokeBorder(Palette.border, lineWidth: Metrics.border))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch kind {
        case .error: "exclamationmark.square.fill"
        case .info: "info.square.fill"
        case .success: "checkmark.square.fill"
        }
    }

    private var edge: Color {
        switch kind {
        case .error: Palette.accent
        case .info, .success: Palette.ink
        }
    }

    @ViewBuilder
    private var surface: some View {
        switch kind {
        case .error: Palette.page
        case .info: Palette.muted
        case .success: Palette.ink
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

/// A plain-list row that pushes `value` without the system disclosure chevron.
struct PushRow<Value: Hashable, Content: View>: View {
    let value: Value
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            NavigationLink(value: value) { EmptyView() }.opacity(0)
            content()
        }
    }
}

// MARK: - Fields

extension ButtonStyle where Self == DestructiveButtonStyle {
    /// The Swiss Red fill used for the one call to action on a screen.
    static var accent: DestructiveButtonStyle { DestructiveButtonStyle() }
}

/// A text field as a rule with text on it. Focus turns the rule red.
struct UnderlinedField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var secure = false
    var meta: String? = nil
    var configure: (AnyView) -> AnyView = { $0 }
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text(label).eyebrowStyle(color: Palette.ink)
                Spacer()
                if let meta {
                    Text(meta).font(Typography.meta).foregroundStyle(Palette.secondary)
                }
            }
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(Typography.body)
            .foregroundStyle(Palette.ink)
            .textFieldStyle(.plain)
            .focused($focused)
            .frame(minHeight: Metrics.touchTarget - 8)
            Rectangle()
                .fill(focused ? Palette.accent : Palette.ink)
                .frame(height: Metrics.border)
                .animation(.linear(duration: 0.1), value: focused)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Uppercase, ruled header used at the top of a plain-list section.
struct SectionHeaderRow: View {
    let number: String?
    let eyebrow: String
    let title: String
    var description: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionLabel(number, eyebrow)
                    Text(title)
                        .headlineStyle(Typography.title)
                        .accessibilityAddTraits(.isHeader)
                    if let description {
                        Text(description)
                            .font(Typography.meta)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.m)
            Rule(width: Metrics.borderHeavy)
        }
    }
}
