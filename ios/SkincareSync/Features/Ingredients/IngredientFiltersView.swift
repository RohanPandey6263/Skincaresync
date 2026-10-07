import SwiftUI

/// Filter sheet: functions, source, engine-only and restricted-only.
struct IngredientFiltersView: View {
    let model: IngredientsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = IngredientQuery()
    @State private var functionSearch = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionLabel("01", "Scope")
                        Toggle("Only ingredients with interaction rules", isOn: $draft.onlyWithInteractions)
                        Toggle("Only restricted ingredients", isOn: $draft.onlyRestricted)
                        Text("Interaction rules power the compatibility engine. Restrictions come from the CosIng regulatory annex.")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Typography.body)
                    .tint(Palette.cocoa)
                    .padding(Spacing.m)
                    .softCard()
                    .cardGutter()
                    .padding(.top, Spacing.m)

                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionLabel("02", "Source")
                        Picker("Source", selection: $draft.source) {
                            Text("Any").tag(String?.none)
                            Text("Curated").tag(String?.some("curated"))
                            Text("Open Beauty Facts").tag(String?.some("open-beauty-facts"))
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Source")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.m)
                    .softCard()
                    .cardGutter()

                    functionsSection
                }
            }
            .background(Palette.page)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { draft = IngredientQuery() }
                        .font(Typography.control)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        model.apply(filters: draft)
                        dismiss()
                    }
                    .font(Typography.control)
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
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                SectionLabel("03", "Functions")
                Spacer()
                if !draft.functions.isEmpty {
                    Text("\(draft.functions.count) selected").font(Typography.meta).foregroundStyle(Palette.secondary)
                }
            }
            switch model.facets {
            case .idle, .loading:
                HStack(spacing: Spacing.s) {
                    ProgressView().tint(Palette.ink)
                    Text("Loading functions…").eyebrowStyle()
                }
            case .failed(let error):
                InlineNotice(kind: .error, text: "Functions unavailable. \(error.message)", actionTitle: "Retry") {
                    model.loadFacets()
                }
            case .loaded(let facets):
                UnderlinedField(label: "Filter functions", text: $functionSearch, placeholder: "e.g. antioxidant")
                FlowLayout(spacing: Spacing.s) {
                    ForEach(visibleFunctions(facets)) { function in
                        ChipToggle(
                            title: "\(IngredientFormatting.functionLabel(function.value)) \(function.count.formatted())",
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
                Text("An ingredient matches when it has any selected function.")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .softCard()
        .cardGutter()
        .padding(.bottom, Spacing.xl)
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
