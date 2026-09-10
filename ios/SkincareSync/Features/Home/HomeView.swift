import SwiftUI

struct HomeView: View {
    @Environment(\.api) private var api
    @Environment(AppNavigation.self) private var navigation
    @State private var model: HomeViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hero
                    Hairline()
                    howItWorks
                    Hairline()
                    statusLine
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
            .background(Palette.page)
            .navigationTitle("SkincareSync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.page, for: .navigationBar)
        }
        .task {
            if model == nil { model = HomeViewModel(api: api) }
            model?.load()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Ingredient interaction engine").eyebrowStyle()
            Text("Find the conflicts hiding in your skincare routine.")
                .font(Typography.display)
                .foregroundStyle(Palette.forest)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("SkincareSync checks the real ingredient lists of the products you use, inside your morning routine, inside your evening routine, and across both, against cited interaction rules.")
                .font(Typography.body)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                navigation.selectedTab = .routine
            } label: {
                Label("Analyze my routine", systemImage: "arrow.right")
                    .labelStyle(.titleOnly)
            }
            .buttonStyle(.primary)
            .padding(.top, Spacing.s)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("How it works").eyebrowStyle()
            VStack(alignment: .leading, spacing: 0) {
                HowItWorksRow(number: 1, title: "Identify products",
                              detail: "Search by name, scan a barcode, or paste the list from the packaging.")
                Hairline()
                HowItWorksRow(number: 2, title: "Find ingredients",
                              detail: "Each INCI list is parsed and matched against a catalog of 22,000 names.")
                Hairline()
                HowItWorksRow(number: 3, title: "Apply cited rules",
                              detail: "Every conflict, caution and synergy links to the study behind it.")
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model?.health ?? .idle {
        case .idle, .loading:
            Text("Checking the engine…")
                .font(Typography.meta)
                .foregroundStyle(Palette.faint)
                .accessibilityLabel("Checking the engine")
        case .loaded(let status):
            if let line = HomeViewModel.statusLine(for: status) {
                Text(line)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.faint)
            } else {
                InlineNotice(kind: .error, text: "The engine's database is unavailable right now.",
                             actionTitle: "Retry") { model?.load() }
            }
        case .failed(let error):
            InlineNotice(kind: .error, text: "\(error.title). \(error.message)",
                         actionTitle: "Retry") { model?.load() }
        }
    }
}

private struct HowItWorksRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Text(String(number))
                .font(Typography.heading)
                .foregroundStyle(Palette.sage)
                .frame(width: 24, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.forest)
                Text(detail)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(title). \(detail)")
    }
}

#Preview("Loaded") {
    HomeView()
        .environment(\.api, MockAPIClient())
        .environment(AppNavigation())
}

#Preview("Unreachable") {
    HomeView()
        .environment(\.api, MockAPIClient.failing(.unreachable(host: "127.0.0.1:8000")))
        .environment(AppNavigation())
}
