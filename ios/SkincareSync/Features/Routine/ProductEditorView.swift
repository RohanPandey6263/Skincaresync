import SwiftUI

/// Sheet for one product: find it by search or barcode, or paste the INCI list.
/// Edits write straight through to the store so nothing is lost on dismiss.
struct ProductEditorView: View {
    @Environment(\.api) private var api
    @Environment(\.dismiss) private var dismiss
    @Binding var product: RoutineProduct
    let slot: RoutineSlot
    let onRemove: () -> Void

    @State private var model: ProductEditorViewModel?
    @State private var showScanner = false
    @State private var confirmRemove = false
    @FocusState private var focus: Field?

    private enum Field { case brand, name, ingredients }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                resultsSection
                ingredientSection
                Section {
                    Button("Remove product", role: .destructive) { confirmRemove = true }
                        .frame(minHeight: Metrics.touchTarget - 12)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.page)
            .navigationTitle(product.trimmedName.isEmpty ? "\(slot.title) product" : product.trimmedName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
            .confirmationDialog("Remove this product from the \(slot.title.lowercased()) routine?",
                                isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    onRemove()
                    dismiss()
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerSheet { match in
                    product.apply(match)
                    model?.clearSearch()
                }
            }
        }
        .task {
            if model == nil { model = ProductEditorViewModel(api: api) }
            if product.trimmedName.isEmpty { focus = .name }
        }
        .onDisappear { model?.cancelAll() }
    }

    // MARK: Sections

    private var identitySection: some View {
        Section {
            TextField("Brand (optional)", text: $product.brand)
                .textContentType(.organizationName)
                .autocorrectionDisabled()
                .focused($focus, equals: .brand)
                .submitLabel(.next)
                .onSubmit { focus = .name }
            TextField("Product name", text: $product.name)
                .autocorrectionDisabled()
                .focused($focus, equals: .name)
                .submitLabel(.search)
                .onSubmit { runSearch() }
            HStack(spacing: Spacing.s) {
                Button {
                    runSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.secondary)
                Button {
                    showScanner = true
                } label: {
                    Label("Scan barcode", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(.secondary)
            }
            .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.m, bottom: Spacing.s, trailing: Spacing.m))
            .listRowBackground(Color.clear)
            if let hint = model?.searchHint {
                Text(hint)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.terracottaText)
            }
        } header: {
            Text("Find the product")
        } footer: {
            Text("Search checks the SkincareSync catalog, FDA DailyMed labels and Open Beauty Facts. Misspellings such as “tretinion” are tolerated.")
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch model?.search ?? .idle {
        case .idle:
            EmptyView()
        case .loading:
            Section("Results") {
                HStack(spacing: Spacing.s) {
                    ProgressView()
                    Text("Searching product sources…")
                        .font(Typography.meta)
                        .foregroundStyle(Palette.muted)
                }
                .accessibilityElement(children: .combine)
            }
        case .empty:
            Section("Results") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("No ingredient list found")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.forest)
                    Text("Try the brand and product name from the packaging, scan the barcode, or paste the ingredient list below.")
                        .font(Typography.meta)
                        .foregroundStyle(Palette.muted)
                }
                .padding(.vertical, Spacing.xs)
            }
        case .failed(let error):
            Section("Results") {
                InlineNotice(kind: .error, text: "\(error.title). \(error.message)", actionTitle: "Retry") {
                    runSearch()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        case .results(let matches):
            Section {
                ForEach(matches) { match in
                    Button {
                        product.apply(match)
                        model?.clearSearch()
                        Haptics.success()
                        focus = nil
                    } label: {
                        ProductMatchRow(match: match, isSelected: match.code != nil && match.code == product.code)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Uses this product's ingredient list")
                }
            } header: {
                Text("Results")
            } footer: {
                Text("Choose a match to load its ingredient list. Packaging is always the source of truth.")
            }
        }
    }

    private var ingredientSection: some View {
        Section {
            TextEditor(text: $product.rawIngredientList)
                .font(.body)
                .frame(minHeight: 120)
                .focused($focus, equals: .ingredients)
                .accessibilityLabel("Ingredient list")
            HStack(spacing: Spacing.xs) {
                Image(systemName: product.hasIngredients ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(product.hasIngredients ? Palette.sage : Palette.terracotta)
                    .accessibilityHidden(true)
                Text(ingredientStatus)
                    .font(Typography.meta)
                    .foregroundStyle(product.hasIngredients ? Palette.sageText : Palette.terracottaText)
            }
            .accessibilityElement(children: .combine)
            if let url = safeURL(product.productUrl) {
                Link(destination: url) {
                    Label("View source page", systemImage: "arrow.up.right.square")
                        .font(Typography.meta)
                }
                .frame(minHeight: Metrics.touchTarget - 12)
            }
        } header: {
            Text("Ingredient list")
        } footer: {
            Text("Paste the INCI list from the packaging if search cannot find it. Separate ingredients with commas.")
        }
    }

    private var ingredientStatus: String {
        guard product.hasIngredients else { return "No ingredient list yet" }
        let count = product.ingredientCount
        var text = "\(count) ingredient\(count == 1 ? "" : "s")"
        if let source = product.source, !source.isEmpty {
            text += " · from \(ProductMatch(code: nil, brand: "", name: "", rawIngredientList: "", source: source).sourceLabel)"
        }
        return text
    }

    private func runSearch() {
        focus = nil
        model?.searchProducts(brand: product.brand, name: product.name)
    }
}

/// Only plain web URLs are ever opened; product pages come from user-editable sources.
func safeURL(_ value: String?) -> URL? {
    guard let value, let url = URL(string: value), let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https", url.host != nil
    else { return nil }
    return url
}

struct ProductMatchRow: View {
    let match: ProductMatch
    var isSelected = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            AsyncImage(url: safeURL(match.imageUrl)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(Palette.faint)
                }
            }
            .frame(width: 44, height: 44)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(match.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.forest)
                if !match.brand.isEmpty {
                    Text(match.brand)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.muted)
                }
                Text(detailLine)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.faint)
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Palette.sageText)
                    .accessibilityLabel("Selected")
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: Metrics.touchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        let count = IngredientCounter.count(match.rawIngredientList)
        var parts = ["\(count) ingredients", match.sourceLabel]
        if let score = match.similarityScore { parts.append("\(score)% match") }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    struct Host: View {
        @State private var product = RoutineProduct(brand: "CeraVe", name: "Hydrating Cleanser")
        var body: some View {
            ProductEditorView(product: $product, slot: .am) {}
                .environment(\.api, MockAPIClient())
        }
    }
    return Host()
}
