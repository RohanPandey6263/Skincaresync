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
                    ProgressView()
                }
            }
            .background(Palette.page)
            .navigationTitle("Ingredients")
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
            Section {
                letterStrip(model)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if let error = model.inlineError {
                Section {
                    InlineNotice(kind: .error, text: "Couldn't refresh. \(error.message)", actionTitle: "Retry") { model.retry() }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            resultsSection(model)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search ingredients")
        .searchSuggestions {
            ForEach(model.suggestions) { suggestion in
                Button {
                    model.choose(suggestion: suggestion)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.displayName).foregroundStyle(Palette.forest)
                        if let category = suggestion.category {
                            Text(IngredientFormatting.functionLabel(category)).font(Typography.meta).foregroundStyle(Palette.muted)
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

    private func letterStrip(_ model: IngredientsViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(Self.letters, id: \.self) { letter in
                    let selected = model.selectedLetter == letter
                    Button {
                        model.setLetter(letter)
                    } label: {
                        Text(letter)
                            .font(.callout.weight(selected ? .bold : .regular))
                            .foregroundStyle(selected ? Palette.onForest : Palette.forest)
                            .frame(minWidth: 36, minHeight: Metrics.touchTarget - 8)
                            .background(selected ? Palette.forest : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(letter == "#" ? "Names starting with a number or symbol" : "Names starting with \(letter)")
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
        }
    }

    @ViewBuilder
    private func resultsSection(_ model: IngredientsViewModel) -> some View {
        switch model.phase {
        case .idle, .loading:
            Section { SkeletonRows() }
        case .failed(let error):
            Section {
                ErrorStateView(error: error) { model.retry() }
                    .listRowSeparator(.hidden)
            }
        case .empty:
            Section {
                EmptyStateView(
                    symbol: "leaf",
                    title: "No ingredients match",
                    message: model.query.isEmpty && model.activeFilterCount == 0
                        ? "The catalog returned nothing. Pull to refresh."
                        : "Try another spelling or clear the filters.",
                    actionTitle: model.query.isEmpty && model.activeFilterCount == 0 ? nil : "Clear search and filters",
                    action: model.query.isEmpty && model.activeFilterCount == 0 ? nil : { model.clearAll() }
                )
                .listRowSeparator(.hidden)
            }
        case .loaded:
            Section {
                ForEach(model.items) { item in
                    NavigationLink(value: item.id) {
                        IngredientRow(item: item)
                    }
                    .onAppear { model.loadMoreIfNeeded(current: item) }
                }
                loadMoreRow(model)
            } header: {
                if let total = model.total {
                    Text("\(total.formatted()) result\(total == 1 ? "" : "s")")
                        .font(Typography.meta)
                        .foregroundStyle(Palette.faint)
                        .textCase(nil)
                }
            }
        }
    }

    @ViewBuilder
    private func loadMoreRow(_ model: IngredientsViewModel) -> some View {
        switch model.loadMore {
        case .loading:
            HStack(spacing: Spacing.s) {
                ProgressView()
                Text("Loading more…").font(Typography.meta).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .combine)
        case .failed(let error):
            InlineNotice(kind: .error, text: "Couldn't load more. \(error.message)", actionTitle: "Retry") { model.loadNextPage() }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        case .idle:
            if model.hasMore {
                Button("Load more") { model.loadNextPage() }
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.sageText)
                    .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget)
                    .listRowSeparator(.hidden)
            }
        }
    }
}

struct IngredientRow: View {
    let item: IngredientSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(item.displayName)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.forest)
            if !item.functions.isEmpty {
                Text(item.functions.prefix(3).map(IngredientFormatting.functionLabel).joined(separator: " · "))
                    .font(Typography.meta)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
            if item.isCurated || item.isInEngine || item.isRestricted {
                FlowLayout(spacing: Spacing.xs) {
                    if item.isInEngine { TagPill(text: "\(item.interactionCount) rule\(item.interactionCount == 1 ? "" : "s")", symbol: "link") }
                    if item.isCurated { TagPill(text: "Curated") }
                    if item.isRestricted { TagPill(text: "Restricted", symbol: "exclamationmark.triangle", tone: Severity.medium.presentation) }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    IngredientsView()
        .environment(\.api, MockAPIClient())
        .environment(AppNavigation())
}
