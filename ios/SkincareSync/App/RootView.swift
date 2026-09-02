import SwiftUI

struct RootView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(SessionStore.self) private var session

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.selectedTab) {
            RoutineView()
                .tabItem { Label("Routine", systemImage: "list.bullet.rectangle.fill") }
                .tag(AppTab.routine)
            IngredientsView()
                .tabItem { Label("Ingredients", systemImage: "magnifyingglass") }
                .tag(AppTab.ingredients)
            AccountView()
                .tabItem { Label("Account", systemImage: "person.fill") }
                .tag(AppTab.account)
        }
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
}

#Preview {
    RootView()
        .environment(\.api, MockAPIClient())
        .environment(SessionStore(api: MockAPIClient()))
        .environment(RoutineStore(api: MockAPIClient(), draftStore: InMemoryDraftStore(initial: Fixtures.sampleDraft)))
        .environment(AppNavigation())
}
