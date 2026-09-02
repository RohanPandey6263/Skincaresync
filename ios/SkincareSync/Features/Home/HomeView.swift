import SwiftUI

struct HomeView: View {
    @Environment(\.api) private var api
    @Environment(AppNavigation.self) private var navigation
    @State private var model: HomeViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    Rule(width: Metrics.borderHeavy)
                    composition
                    Rule(width: Metrics.borderHeavy)
                    facts
                    method
                    colophon
                }
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

    // MARK: 01 Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SectionLabel("01", "Ingredient interaction engine")
            (Text("Find the ") + Text("conflicts").foregroundStyle(Palette.accent) + Text(" hiding in your routine."))
                .headlineStyle(Typography.display)
                .accessibilityAddTraits(.isHeader)
            Text("SkincareSync checks the real ingredient lists of the products you use, inside your morning routine, inside your evening routine, and across both, against cited interaction rules.")
                .font(Typography.body)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                navigation.selectedTab = .routine
            } label: {
                HStack {
                    Text("Analyze my routine")
                    Spacer()
                    Image(systemName: "arrow.right").font(.body.weight(.bold))
                }
            }
            .buttonStyle(.primary)
        }
        .padding(Spacing.m)
        .padding(.top, Spacing.m)
    }

    /// Abstract composition: a black mass, a red circle, rules. Ornament only.
    private var composition: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Palette.ink)
                    .frame(width: w * 0.42, height: h * 0.62)
                    .offset(x: w * 0.08, y: h * 0.1)
                Rectangle().fill(Palette.page)
                    .frame(width: w * 0.16, height: h * 0.2)
                    .offset(x: w * 0.19, y: h * 0.28)
                Circle().fill(Palette.accent)
                    .frame(width: h * 0.46, height: h * 0.46)
                    .overlay(Circle().stroke(Palette.accent.opacity(0.12), lineWidth: 8))
                    .offset(x: w * 0.5, y: h * 0.2)
                Rectangle().fill(Palette.ink).frame(height: Metrics.borderHeavy).offset(y: h * 0.78)
                Rectangle().fill(Palette.ink).frame(height: Metrics.border).offset(y: h * 0.86)
                Rectangle().fill(Palette.ink).frame(width: 22, height: 22).offset(x: w - 22 - w * 0.08, y: h * 0.9 - 22)
                Text("AM · PM · Cumulative")
                    .eyebrowStyle(color: Palette.ink)
                    .offset(x: w * 0.08, y: h * 0.9 - 8)
            }
        }
        .frame(height: 240)
        .swissGrid()
        .accessibilityHidden(true)
    }

    // MARK: Facts (live counts)

    @ViewBuilder
    private var facts: some View {
        switch model?.health ?? .idle {
        case .idle, .loading:
            factRows(["Checking the engine…"], loading: true)
        case .loaded(let status):
            if status.ok, let ingredients = status.ingredientCount, let products = status.productCount, let rules = status.interactionCount {
                factRows([
                    "\(ingredients.formatted()) ingredients indexed",
                    "\(products.formatted()) product ingredient lists",
                    "\(rules.formatted()) cited interaction rules",
                    "Checked within AM, within PM and across both",
                ])
            } else {
                InlineNotice(kind: .error, text: "The engine's database is unavailable right now.", actionTitle: "Retry") { model?.load() }
                    .padding(Spacing.m)
            }
        case .failed(let error):
            InlineNotice(kind: .error, text: "\(error.title). \(error.message)", actionTitle: "Retry") { model?.load() }
                .padding(Spacing.m)
        }
    }

    private func factRows(_ items: [String], loading: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, fact in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    Text(String(format: "%02d", index + 1))
                        .eyebrowStyle(color: Palette.accentText)
                        .accessibilityHidden(true)
                    Text(fact)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(loading ? Palette.faint : Palette.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.m)
                .accessibilityElement(children: .combine)
                Rule()
            }
        }
        .swissGrid()
    }

    // MARK: 02 Method

    private var method: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionLabel("02", "Method")
                Text("Three steps. No guesswork.")
                    .headlineStyle(Typography.title)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(Spacing.m)
            .padding(.top, Spacing.l)
            Rule(width: Metrics.borderHeavy)
            MethodRow(number: 1, title: "Identify products",
                      detail: "Search by name, scan a barcode, or paste the list from the packaging.")
            MethodRow(number: 2, title: "Find ingredients",
                      detail: "Each INCI list is parsed and matched against a catalog of 22,000 names.")
            MethodRow(number: 3, title: "Apply cited rules",
                      detail: "Every conflict, caution and synergy links to the study behind it.")
        }
    }

    private var colophon: some View {
        Text("The engine is deterministic: the same routine and the same skin profile always produce the same report.")
            .font(Typography.meta)
            .foregroundStyle(Palette.faint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Spacing.m)
            .padding(.bottom, Spacing.xl)
    }
}

private struct MethodRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Text(String(format: "%02d", number))
                    .font(Typography.numeral)
                    .foregroundStyle(Palette.ink.opacity(0.15))
                    .frame(width: 72, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .headlineStyle(Typography.heading)
                    Text(detail)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.m)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(number). \(title). \(detail)")
            Rule()
        }
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
