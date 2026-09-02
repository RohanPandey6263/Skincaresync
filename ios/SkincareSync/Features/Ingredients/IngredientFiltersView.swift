import SwiftUI

/// Filter sheet: functions, source, engine-only and restricted-only.
struct IngredientFiltersView: View {
    let model: IngredientsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = IngredientQuery()
    @State private var functionSearch = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Only ingredients with interaction rules", isOn: $draft.onlyWithInteractions)
                    Toggle("Only restricted ingredients", isOn: $draft.onlyRestricted)
                } footer: {
                    Text("Interaction rules power the compatibility engine. Restrictions come from the CosIng regulatory annex.")
                }
                Section("Source") {
                    Picker("Source", selection: $draft.source) {
                        Text("Any").tag(String?.none)
                        Text("Curated").tag(String?.some("curated"))
                        Text("Open Beauty Facts").tag(String?.some("open-beauty-facts"))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Source")
                }
                functionsSection
            }
            .scrollContentBackground(.hidden)
            .background(Palette.page)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        draft = IngredientQuery()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        model.apply(filters: draft)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .onAppear {
            draft = model.filters
            model.loadFacets()
        }
    }

    @ViewBuilder
    private var functionsSection: some View {
        Section {
            switch model.facets {
            case .idle, .loading:
                HStack(spacing: Spacing.s) {
                    ProgressView()
                    Text("Loading functions…").font(Typography.meta).foregroundStyle(Palette.muted)
                }
            case .failed(let error):
                InlineNotice(kind: .error, text: "Functions unavailable. \(error.message)", actionTitle: "Retry") {
                    model.loadFacets()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            case .loaded(let facets):
                TextField("Filter functions", text: $functionSearch)
                    .autocorrectionDisabled()
                FlowLayout(spacing: Spacing.s) {
                    ForEach(visibleFunctions(facets)) { function in
                        ChipToggle(
                            title: "\(IngredientFormatting.functionLabel(function.value)) (\(function.count.formatted()))",
                            isOn: Binding(
                                get: { draft.functions.contains(function.value) },
                                set: { selected in
                                    if selected {
                                        if !draft.functions.contains(function.value) { draft.functions.append(function.value) }
                                    } else {
                                        draft.functions.removeAll { $0 == function.value }
                                    }
                                }
                            )
                        )
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        } header: {
            Text(draft.functions.isEmpty ? "Functions" : "Functions (\(draft.functions.count) selected)")
        } footer: {
            Text("An ingredient matches when it has any selected function.")
        }
    }

    private func visibleFunctions(_ facets: CatalogFacets) -> [CatalogFacets.FunctionCount] {
        let needle = functionSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let all = facets.functions
        if needle.isEmpty { return Array(all.prefix(40)) }
        return all.filter { $0.value.replacingOccurrences(of: "-", with: " ").contains(needle) }
    }
}

#Preview {
    IngredientFiltersView(model: IngredientsViewModel(api: MockAPIClient()))
}
