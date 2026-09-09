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
    @FocusState private var ingredientsFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    identitySection
                    resultsSection
                    ingredientSection
                    Button("Remove product") { confirmRemove = true }
                        .buttonStyle(.destructive)
                        .cardGutter()
                        .padding(.bottom, Spacing.xl)
                }
                .padding(.top, Spacing.m)
            }
            .background(Palette.page)
            .navigationTitle(product.trimmedName.isEmpty ? "\(slot.title) product" : product.trimmedName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Typography.control)
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
        }
        .onDisappear { model?.cancelAll() }
    }

    // MARK: Sections

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SectionLabel("01", "Find the product")
            UnderlinedField(label: "Brand", text: $product.brand, placeholder: "Optional", meta: nil)
            UnderlinedField(label: "Product name", text: $product.name, placeholder: "Required")
            HStack(spacing: Spacing.s) {
                Button {
                    runSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.primary)
                Button {
                    showScanner = true
                } label: {
                    Label("Scan", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(.secondary)
            }
            if let hint = model?.searchHint {
                Text(hint)
                    .font(Typography.metaBold)
                    .foregroundStyle(Palette.accentText)
            }
            Text("Search checks the SkincareSync catalog, FDA DailyMed labels and Open Beauty Facts.")
                .font(Typography.meta)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.m)
        .softCard()
        .cardGutter()
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch model?.search ?? .idle {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: Spacing.s) {
                ProgressView().tint(Palette.ink)
                Text("Searching product sources…").eyebrowStyle(color: Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
            .softCard()
            .cardGutter()
            .accessibilityElement(children: .combine)
        case .empty:
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("No ingredient list found").headlineStyle(Typography.heading)
                Text("Try the brand and product name from the packaging, scan the barcode, or paste the ingredient list below.")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .swissGrid(radius: Radius.card)
            .cardGutter()
        case .failed(let error):
            InlineNotice(kind: .error, text: "\(error.title). \(error.message)", actionTitle: "Retry") { runSearch() }
                .cardGutter()
        case .results(let matches):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionLabel(nil, "Results")
                    Spacer()
                    Text("\(matches.count)").eyebrowStyle(color: Palette.faint)
                }
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.m)
                .padding(.bottom, Spacing.s)
                ForEach(matches) { match in
                    Button {
                        product.apply(match)
                        model?.clearSearch()
                        Haptics.success()
                    } label: {
                        ProductMatchRow(match: match, isSelected: match.code != nil && match.code == product.code)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Uses this product's ingredient list")
                }
                Text("Choose a match to load its ingredient list. Packaging is always the source of truth.")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.faint)
                    .padding(Spacing.m)
            }
            .softCard()
            .cardGutter()
        }
    }

    private var ingredientSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionLabel("02", "Ingredient list")
                TextEditor(text: $product.rawIngredientList)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(Spacing.s + 2)
                    .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    .softOutline(radius: Radius.field,
                                 color: ingredientsFocused ? Palette.accent : Palette.outline,
                                 width: ingredientsFocused ? 2 : Metrics.border)
                    .animation(.easeOut(duration: 0.14), value: ingredientsFocused)
                    .focused($ingredientsFocused)
                    .accessibilityLabel("Ingredient list")
                HStack(spacing: Spacing.xs + 2) {
                    StatusDot(color: product.hasIngredients ? Palette.mint : Palette.accent)
                    Text(ingredientStatus)
                        .font(Typography.metaBold)
                        .foregroundStyle(product.hasIngredients ? Palette.secondary : Palette.accentText)
                }
                .accessibilityElement(children: .combine)
                if let url = safeURL(product.productUrl) {
                    Link(destination: url) {
                        HStack(spacing: Spacing.xs) {
                            Text("View source page")
                            Image(systemName: "arrow.up.right")
                        }
                        .eyebrowStyle(color: Palette.accentText)
                        .frame(minHeight: Metrics.touchTarget - 12)
                    }
                }
                Text("Paste the INCI list from the packaging if search cannot find it. Separate ingredients with commas.")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.m)
        }
        .softCard()
        .cardGutter()
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.m) {
                AsyncImage(url: safeURL(match.imageUrl)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(Palette.faint)
                    }
                }
                .frame(width: 48, height: 48)
                .background(Palette.muted)
                .softClip(radius: Radius.small)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(match.name)
                        .headlineStyle(Typography.pairName)
                        .lineLimit(2)
                    if !match.brand.isEmpty {
                        Text(match.brand)
                            .font(Typography.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                    Text(detailLine)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
                if isSelected {
                    CheckCircle(isOn: true)
                        .accessibilityHidden(false)
                        .accessibilityLabel("Selected")
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.m - 2)
            .frame(minHeight: Metrics.touchTarget)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            Rule().padding(.leading, Spacing.m)
        }
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
