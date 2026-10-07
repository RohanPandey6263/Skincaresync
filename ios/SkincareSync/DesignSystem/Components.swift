import SwiftUI

// MARK: - Surfaces

extension View {
    /// The unit of layout: a rounded card cut from `Palette.surface`, lifted off
    /// the page by a soft ambient shadow rather than by an outline.
    func softCard(radius: CGFloat = Radius.card,
                  fill: Color = Palette.surface,
                  shadow: Bool = true) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: shadow ? Palette.shadow : .clear, radius: 14, x: 0, y: 6)
    }

    /// A hairline outline on a rounded shape, for controls that need an edge.
    func softOutline(radius: CGFloat = Radius.tile,
                     color: Color = Palette.border,
                     width: CGFloat = Metrics.border) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: width)
        )
    }

    /// Clips content to the card corner, so a fill or a pattern follows the shape.
    func softClip(radius: CGFloat = Radius.card) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Buttons

/// Filled ink pill for the one primary action on a screen. Pressing dims and
/// settles it rather than inverting: the motion is soft now, not a snap.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .controlLabelStyle(color: Palette.onInk)
            .frame(maxWidth: .infinity, minHeight: Metrics.controlHeight)
            .padding(.horizontal, Spacing.l)
            .background(Palette.ink, in: Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule(style: .continuous))
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Outlined pill on the card surface. Pressing fills it with sand.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .controlLabelStyle()
            .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget + 8)
            .padding(.horizontal, Spacing.l)
            .background(configuration.isPressed ? Palette.muted : Palette.surface, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.outline, lineWidth: Metrics.border))
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule(style: .continuous))
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Coral pill. Reserved for the one call to action, sign-out and account removal.
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .controlLabelStyle(color: Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: Metrics.controlHeight)
            .padding(.horizontal, Spacing.l)
            .background(Palette.accent, in: Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule(style: .continuous))
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
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
    /// The coral fill used for the one call to action on a screen.
    static var accent: DestructiveButtonStyle { DestructiveButtonStyle() }
}

/// A circular icon button — the small round chrome that sits on a card.
struct CircleIconButton: View {
    let symbol: String
    let label: String
    var tone: Color = Palette.ink
    var background: Color = Palette.muted
    var size: CGFloat = Metrics.iconButton
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: size, height: size)
                .background(background, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Chips

/// A selectable pill. Selection fills it with ink and shows a check, so the
/// state is never carried by colour alone.
struct ChipToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
            Haptics.selection()
        } label: {
            HStack(spacing: Spacing.xs + 2) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(Typography.control)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(isOn ? Palette.onInk : Palette.ink)
            .padding(.horizontal, Spacing.m + 2)
            .frame(minHeight: Metrics.touchTarget)
            .background(isOn ? Palette.ink : Palette.surface, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(isOn ? .clear : Palette.outline, lineWidth: Metrics.border))
            .contentShape(Capsule(style: .continuous))
            .animation(.easeOut(duration: 0.16), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
    }
}

/// Static informational pill ("Curated", "High severity"). Outlined by default,
/// filled with a wash of the tone when it needs to carry a verdict.
struct TagPill: View {
    let text: String
    var symbol: String? = nil
    var tone: TonePresentation? = nil
    /// When true the tag is filled with the tone's tint instead of outlined.
    var filled = false

    var body: some View {
        HStack(spacing: Spacing.xs + 1) {
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
        .foregroundStyle(filled ? (tone?.onTint ?? Palette.onInk) : (tone?.text ?? Palette.secondary))
        .padding(.horizontal, Spacing.s + 4)
        .padding(.vertical, Spacing.xs + 3)
        .background(fill, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(filled ? .clear : Palette.outline, lineWidth: Metrics.border))
        .accessibilityElement(children: .combine)
    }

    private var fill: Color {
        if filled { return tone?.tint ?? Palette.ink }
        return Palette.surface
    }
}

/// A small round status dot. Always sits beside the words it qualifies.
struct StatusDot: View {
    var color: Color = Palette.ink
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The round check that marks a chosen item, the way a checklist does.
struct CheckCircle: View {
    var isOn: Bool
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? Palette.ink : Color.clear)
                .overlay(Circle().strokeBorder(isOn ? .clear : Palette.outline, lineWidth: 1.5))
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(Palette.onInk)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Structure

/// Numbered section label: "01 Profile". Cocoa numeral, tracked uppercase word.
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
                Text(number)
                    .foregroundStyle(Palette.cocoa)
            }
            Text(title)
                .foregroundStyle(Palette.secondary)
        }
        .font(Typography.eyebrow)
        .textCase(.uppercase)
        .kerning(Typography.labelTracking)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(number.map { "Section \($0), \(title)" } ?? title)
    }
}

/// A rounded card that frames a group of content, with a labelled header.
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
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.m)
            }
            content()
        }
        .softCard(shadow: !heavy)
        .softOutline(radius: Radius.card, color: heavy ? Palette.outline : Palette.border)
    }
}

/// A hairline separator. Weight comes from surface and space now, so a rule is
/// always thin.
struct Rule: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: Metrics.hairline)
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

/// A list row that draws its own hairline beneath, for plain lists.
struct RuledRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            Rule()
        }
    }
}

extension View {
    /// Removes the system separators and insets so a plain list can carry its
    /// own cards and hairlines.
    func swissRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }

    /// The standard gutter a card keeps from the edge of the screen.
    func cardGutter() -> some View {
        padding(.horizontal, Spacing.m)
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
        VStack(spacing: Spacing.s) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Capsule().fill(Palette.muted).frame(width: 180, height: 16)
                    Capsule().fill(Palette.muted).frame(width: 260, height: 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.l)
                .softCard(radius: Radius.tile)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// An icon enclosed in a soft circle.
struct IconBox: View {
    let symbol: String
    var tone: TonePresentation? = nil
    var filled = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(filled ? (tone?.onTint ?? Palette.onInk) : (tone?.text ?? Palette.ink))
            .frame(width: 48, height: 48)
            .background(background, in: Circle())
            .accessibilityHidden(true)
    }

    private var background: Color {
        if filled { return tone?.tint ?? Palette.ink }
        if let tone { return Palette.wash(tone.tint) }
        return Palette.muted
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
        .softCard()
        .cardGutter()
        .padding(.vertical, Spacing.l)
    }
}

/// Inline, recoverable error on a coral wash, with a retry.
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
        .softCard()
        .softOutline(radius: Radius.card, color: Palette.accent.opacity(0.6))
        .cardGutter()
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
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s + 2) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(iconTone)
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.meta)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Typography.metaBold)
                    .foregroundStyle(Palette.ink)
                    .frame(minHeight: Metrics.touchTarget - 12)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.vertical, Spacing.m - 2)
        .padding(.horizontal, Spacing.m)
        .background(surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .softOutline(radius: Radius.tile, color: Palette.border)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch kind {
        case .error: "exclamationmark.circle.fill"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    private var iconTone: Color {
        switch kind {
        case .error: Palette.accentText
        case .info: Palette.cocoa
        case .success: Palette.cocoa
        }
    }

    private var surface: Color {
        switch kind {
        case .error: Palette.wash(Palette.accent)
        case .info: Palette.muted
        case .success: Palette.wash(Palette.mint)
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

/// A rounded text field with its label above it. Focus draws the outline in
/// coral; the name is historical — the rule became a border.
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
                Text(label).eyebrowStyle(color: Palette.secondary)
                Spacer()
                if let meta {
                    Text(meta).font(Typography.meta).foregroundStyle(Palette.faint)
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
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: Metrics.touchTarget + 6)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .softOutline(radius: Radius.field,
                         color: focused ? Palette.accent : Palette.outline,
                         width: focused ? 2 : Metrics.border)
            .animation(.easeOut(duration: 0.14), value: focused)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The header that opens a section: a small tracked label over a big, plain
/// sentence-case title, with optional round chrome on the right.
struct SectionHeaderRow: View {
    let number: String?
    let eyebrow: String
    let title: String
    var description: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
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
        .cardGutter()
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.m)
    }
}
