import SwiftUI

struct RootView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(SessionStore.self) private var session

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "leaf") }
                .tag(AppTab.home)
            RoutineView()
                .tabItem { Label("Routine", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.routine)
            IngredientsView()
                .tabItem { Label("Ingredients", systemImage: "magnifyingglass") }
                .tag(AppTab.ingredients)
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(AppTab.account)
        }
        .tint(Palette.forest)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if navigation.usesFixtureData {
                Text("Fixture data · not the live backend")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.clayText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)
                    .background(Palette.clayWash)
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
