import SwiftUI

/// Three sections behind a tab strip at the top of the window. Every section
/// stays mounted so its navigation state survives switching; only the visible
/// one takes touches.
struct RootView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            TopTabStrip(selection: Binding(get: { navigation.selectedTab }, set: { navigation.selectedTab = $0 }))
            ZStack {
                section(RoutineView(), tab: .routine)
                section(IngredientsView(), tab: .ingredients)
                section(AccountView(), tab: .account)
            }
        }
        .background(Palette.page)
        .tint(Palette.ink)
        .overlay { NoiseOverlay() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if navigation.usesFixtureData {
                Text("Fixture data · not the live backend")
                    .eyebrowStyle(color: Palette.onInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs + 2)
                    .background(Palette.ink)
                    .accessibilityLabel("This build is showing fixture data, not the live backend")
            }
        }
        .task {
            await session.bootstrap()
        }
    }

    private func section<Content: View>(_ content: Content, tab: AppTab) -> some View {
        let visible = navigation.selectedTab == tab
        return content
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}

/// The tab strip: three equal cells on a rule. The active cell is cocoa.
struct TopTabStrip: View {
    @Binding var selection: AppTab

    private let tabs: [(AppTab, String, String)] = [
        (.routine, "Routine", "list.bullet.rectangle.fill"),
        (.ingredients, "Ingredients", "magnifyingglass"),
        (.account, "Account", "person.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.0) { tab, title, symbol in
                    let active = selection == tab
                    Button {
                        if !active {
                            selection = tab
                            Haptics.selection()
                        }
                    } label: {
                        VStack(spacing: Spacing.xs) {
                            Image(systemName: symbol)
                                .font(.footnote.weight(.bold))
                            Text(title)
                                .font(Typography.eyebrow)
                                .textCase(.uppercase)
                                .kerning(Typography.labelTracking)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(active ? Palette.onInk : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget + 8)
                        .background(active ? Palette.cocoa : Palette.page, ignoresSafeAreaEdges: [])
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                    .accessibilityLabel(title)
                    if tab != .account {
                        Rectangle().fill(Palette.cocoa).frame(width: Metrics.border)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Palette.cocoa).frame(height: Metrics.borderHeavy)
        }
        .background(Palette.page.ignoresSafeArea(edges: .top))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }
}

#Preview {
    RootView()
        .environment(\.api, MockAPIClient())
        .environment(SessionStore(api: MockAPIClient()))
        .environment(RoutineStore(api: MockAPIClient(), draftStore: InMemoryDraftStore(initial: Fixtures.sampleDraft)))
        .environment(AppNavigation())
}
