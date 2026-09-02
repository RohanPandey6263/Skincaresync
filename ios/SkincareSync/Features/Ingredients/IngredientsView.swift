import SwiftUI

struct IngredientsView: View {
    @Environment(\.api) private var api
    @Environment(AppNavigation.self) private var navigation
    @State private var model: IngredientsViewModel?
    @State private var showFilters = false
    @State private var path: [Int] = []

    private static let letters = ["#"] + (65...90).map { String(UnicodeScalar($0)!) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView().tint(Palette.ink)
                }
            }
            .background(Palette.page)
            .navigationTitle("Ingredients")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Int.self) { id in
                IngredientDetailView(id: id)
            }
        }
        .task {
            if model == nil { model = IngredientsViewModel(api: api) }
            model?.start()
            if let id = navigation.openIngredientOnLaunch {
                navigation.openIngredientOnLaunch = nil
                path = [id]
            }
        }
    }

    @ViewBuilder
    private func content(_ model: IngredientsViewModel) -> some View {
        @Bindable var model = model
        List {
            SectionHeaderRow(number: "01", eyebrow: "Catalog", title: "Ingredient catalog",
                             description: model.facets.value.map { "\($0.stats.total.formatted()) INCI names from EU CosIng via Open Beauty Facts." })
                .swissRow()
            letterStrip(model)
                .swissRow()
            if let error = model.inlineError {
                InlineNotice(kind: .error, text: "Couldn't refresh. \(error.message)", actionTitle: "Retry") { model.retry() }
                    .padding(Spacing.m)
                    .swissRow()
            }
            resultsSection(model)
            Color.clear.frame(height: Spacing.xl).swissRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search INCI, synonym, or CAS")
        .searchSuggestions {
            ForEach(model.suggestions) { suggestion in
                Button {
                    model.choose(suggestion: suggestion)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.displayName).font(Typography.bodyBold).foregroundStyle(Palette.ink)
                        if let category = suggestion.category {
                            Text(IngredientFormatting.functionLabel(category)).font(Typography.meta).foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
        }
        .onSubmit(of: .search) { model.submit() }
        .onChange(of: model.query) { _, _ in model.queryChanged() }
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilters = true
                } label: {
                    Label(model.activeFilterCount > 0 ? "Filters (\(model.activeFilterCount))" : "Filters",
                          systemImage: model.activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(model.activeFilterCount > 0 ? "Filters, \(model.activeFilterCount) active" : "Filters")
            }
        }
        .sheet(isPresented: $showFilters) {
            IngredientFiltersView(model: model)
        }
    }

    /// A–Z as a strip of squares on a black ground.
    private func letterStrip(_ model: IngredientsViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.border) {
                ForEach(Self.letters, id: \.self) { letter in
                    let selected = model.selectedLetter == letter
                    Button {
                        model.setLetter(letter)
                    } label: {
                        Text(letter)
                            .font(Typography.control)
                            .foregroundStyle(selected ? Palette.onInk : Palette.ink)
                            .frame(width: Metrics.touchTarget, height: Metrics.touchTarget)
                            .background(selected ? Palette.ink : Palette.page)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(letter == "#" ? "Names starting with a number or symbol" : "Names starting with \(letter)")
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(Metrics.border)
            .background(Palette.ink)
        }
        .padding(.vertical, Spacing.m)
        .padding(.horizontal, Spacing.m)
    }

    @ViewBuilder
    private func resultsSection(_ model: IngredientsViewModel) -> some View {
        switch model.phase {
        case .idle, .loading:
            SkeletonRows().padding(.horizontal, Spacing.m).swissRow()
        case .failed(let error):
            ErrorStateView(error: error) { model.retry() }.swissRow()
        case .empty:
            EmptyStateView(
                symbol: "magnifyingglass",
                title: "No ingredients match",
                message: model.query.isEmpty && model.activeFilterCount == 0
                    ? "The catalog returned nothing. Pull to refresh."
                    : "Try another spelling or clear the filters.",
                actionTitle: model.query.isEmpty && model.activeFilterCount == 0 ? nil : "Clear search and filters",
                action: model.query.isEmpty && model.activeFilterCount == 0 ? nil : { model.clearAll() }
            )
            .swissRow()
        case .loaded:
            if let total = model.total {
                HStack {
                    Text("\(total.formatted()) result\(total == 1 ? "" : "s") match").eyebrowStyle(color: Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.s)
                .swissRow()
            }
            Rule(width: Metrics.borderHeavy).swissRow()
            ForEach(model.items) { item in
                PushRow(value: item.id) {
                    IngredientRow(item: item)
                }
                .swissRow()
                .onAppear { model.loadMoreIfNeeded(current: item) }
            }
            loadMoreRow(model).swissRow()
        }
    }

    @ViewBuilder
    private func loadMoreRow(_ model: IngredientsViewModel) -> some View {
        switch model.loadMore {
        case .loading:
            HStack(spacing: Spacing.s) {
                ProgressView().tint(Palette.ink)
                Text("Loading more…").eyebrowStyle()
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.m)
            .accessibilityElement(children: .combine)
        case .failed(let error):
            InlineNotice(kind: .error, text: "Couldn't load more. \(error.message)", actionTitle: "Retry") { model.loadNextPage() }
                .padding(Spacing.m)
        case .idle:
            if model.hasMore {
                Button {
                    model.loadNextPage()
                } label: {
                    Label("Load more", systemImage: "plus")
                }
                .buttonStyle(.secondary)
                .padding(Spacing.m)
            }
        }
    }
}

struct IngredientRow: View {
    let item: IngredientSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(item.displayName)
                        .headlineStyle(Typography.pairName)
                    if !item.functions.isEmpty {
                        Text(item.functions.prefix(3).map(IngredientFormatting.functionLabel).joined(separator: " · "))
                            .font(Typography.meta)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(2)
                    }
                    if item.isCurated || item.isInEngine || item.isRestricted {
                        FlowLayout(spacing: Spacing.m) {
                            if item.isInEngine {
                                HStack(spacing: Spacing.xs) {
                                    Rectangle().fill(Palette.ink).frame(width: 8, height: 8)
                                    Text("\(item.interactionCount) rule\(item.interactionCount == 1 ? "" : "s")")
                                }
                                .eyebrowStyle(color: Palette.ink)
                            }
                            if item.isCurated { Text("Curated").eyebrowStyle(color: Palette.secondary) }
                            if item.isRestricted {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2.weight(.bold))
                                    Text("Restricted")
                                }
                                .eyebrowStyle(color: Palette.accentText)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget + 16, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            Rule()
        }
    }
}

#Preview {
    IngredientsView()
        .environment(\.api, MockAPIClient())
        .environment(AppNavigation())
}
