import SwiftUI

@MainActor
@Observable
final class IngredientDetailViewModel {
    private let api: any APIClient
    let id: Int
    private(set) var state: LoadState<IngredientDetail> = .idle
    private var task: Task<Void, Never>?

    init(api: any APIClient, id: Int) {
        self.api = api
        self.id = id
    }

    func load() {
        guard !state.isLoading else { return }
        task?.cancel()
        state = .loading
        task = Task { [api, id] in
            do {
                let detail = try await api.ingredient(id: id)
                guard !Task.isCancelled else { return }
                state = .loaded(detail)
            } catch let error as APIError {
                if error.isCancellation { return }
                state = .failed(error)
            } catch {
                state = .failed(.invalidResponse)
            }
        }
    }
}

struct IngredientDetailView: View {
    @Environment(\.api) private var api
    let id: Int
    @State private var model: IngredientDetailViewModel?

    var body: some View {
        Group {
            switch model?.state ?? .idle {
            case .idle, .loading:
                ScrollView { SkeletonRows(count: 6).cardGutter().padding(.top, Spacing.m) }
            case .failed(let error):
                ErrorStateView(error: error) { model?.load() }
                    .frame(maxHeight: .infinity, alignment: .top)
            case .loaded(let detail):
                IngredientDetailContent(detail: detail)
            }
        }
        .background(Palette.page)
        .navigationTitle(model?.state.value?.displayName ?? "Ingredient")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) {
            if model?.id != id { model = IngredientDetailViewModel(api: api, id: id) }
            model?.load()
        }
    }
}

private struct DetailSection<Content: View>: View {
    let number: String
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionLabel(number, title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .softCard()
        .cardGutter()
    }
}

private struct IngredientDetailContent: View {
    let detail: IngredientDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text(detail.displayName)
                        .headlineStyle(Typography.title)
                        .accessibilityAddTraits(.isHeader)
                    if detail.inciName != detail.displayName {
                        Text(detail.inciName)
                            .font(Typography.meta)
                            .foregroundStyle(Palette.secondary)
                            .textSelection(.enabled)
                    }
                    if detail.isCurated || detail.isInEngine || detail.isRestricted {
                        FlowLayout(spacing: Spacing.s) {
                            if detail.isCurated { TagPill(text: "Curated", symbol: "checkmark.circle") }
                            if detail.isInEngine { TagPill(text: "In compatibility engine", symbol: "link", filled: true) }
                            if detail.isRestricted { TagPill(text: "Restricted", symbol: "exclamationmark.triangle", tone: Severity.high.presentation) }
                        }
                    }
                    if let description = detail.description, !description.isEmpty {
                        Text(description)
                            .font(Typography.body)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let restriction = detail.restriction, !restriction.isEmpty {
                        InlineNotice(kind: .info, text: restriction)
                    }
                }
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard()
                .cardGutter()
                .padding(.top, Spacing.m)

                DetailSection(number: "01", title: "Details") {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        if let cas = detail.primaryCAS { MetaRow(label: "CAS number", value: cas, monospaced: true) }
                        if let einecs = detail.einecsNumber, !einecs.isEmpty { MetaRow(label: "EINECS", value: einecs, monospaced: true) }
                        if let cosing = detail.cosingRef, !cosing.isEmpty { MetaRow(label: "CosIng reference", value: cosing, monospaced: true) }
                        if let inn = detail.innName, !inn.isEmpty { MetaRow(label: "INN", value: inn) }
                        if let phEur = detail.phEurName, !phEur.isEmpty { MetaRow(label: "Ph. Eur.", value: phEur) }
                        if let category = detail.category { MetaRow(label: "Category", value: IngredientFormatting.functionLabel(category)) }
                        if let comedogenic = detail.comodogenic { MetaRow(label: "Comedogenic rating", value: "\(comedogenic) of 5") }
                        if let min = detail.phMin, let max = detail.phMax {
                            MetaRow(label: "Effective pH", value: "\(min.formatted()) – \(max.formatted())")
                        }
                        MetaRow(label: "Source", value: sourceLine)
                    }
                }

                if !detail.functions.isEmpty {
                    DetailSection(number: "02", title: "Functions") {
                        FlowLayout(spacing: Spacing.s) {
                            ForEach(detail.functions, id: \.self) { function in
                                TagPill(text: IngredientFormatting.functionLabel(function))
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Functions: \(detail.functions.map(IngredientFormatting.functionLabel).joined(separator: ", "))")
                    }
                }

                if !detail.aliases.isEmpty {
                    DetailSection(number: "03", title: "Also known as") {
                        Text(detail.aliases.joined(separator: " · "))
                            .font(Typography.callout)
                            .foregroundStyle(Palette.secondary)
                            .textSelection(.enabled)
                    }
                }

                if !detail.interactions.isEmpty {
                    DetailSection(number: "04", title: "Known interactions (\(detail.interactions.count))") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(detail.interactions) { interaction in
                                InteractionRow(subject: detail.displayName, interaction: interaction)
                            }
                        }
                        Text("Severity shown is the rule's base level; your skin profile can raise it in a report.")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.faint)
                    }
                }

                if !detail.related.isEmpty {
                    DetailSection(number: "05", title: "Related ingredients") {
                        FlowLayout(spacing: Spacing.s) {
                            ForEach(detail.related) { related in
                                NavigationLink(value: related.id) {
                                    Text(related.displayName)
                                        .font(Typography.control)
                                        .foregroundStyle(Palette.ink)
                                        .padding(.horizontal, Spacing.m + 2)
                                        .frame(minHeight: Metrics.touchTarget)
                                        .background(Palette.surfaceAlt, in: Capsule(style: .continuous))
                                        .overlay(Capsule(style: .continuous).strokeBorder(Palette.border, lineWidth: Metrics.border))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if detail.pubChemURL != nil || detail.wikidataURL != nil || detail.openBeautyFactsURL != nil {
                    DetailSection(number: "06", title: "External references") {
                        VStack(spacing: 0) {
                            if let url = detail.pubChemURL { ExternalLinkRow(title: "PubChem", url: url) }
                            if let url = detail.wikidataURL { ExternalLinkRow(title: "Wikidata", url: url) }
                            if let url = detail.openBeautyFactsURL { ExternalLinkRow(title: "Open Beauty Facts", url: url) }
                        }
                        .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                        .softClip(radius: Radius.tile)
                    }
                }
                Color.clear.frame(height: Spacing.l)
            }
        }
    }

    private var sourceLine: String {
        var text = detail.isCurated ? "Curated by SkincareSync" : "Open Beauty Facts / CosIng"
        if let updated = detail.sourceUpdatedOn, !updated.isEmpty { text += " · updated \(updated)" }
        return text
    }
}

private struct InteractionRow: View {
    let subject: String
    let interaction: IngredientInteraction

    var body: some View {
        let tone = interaction.interactionType.presentation(severity: interaction.severity)
        VStack(alignment: .leading, spacing: Spacing.s) {
            TagPill(text: tone.label, symbol: tone.symbol, tone: tone, filled: interaction.interactionType == .conflict)
            NavigationLink(value: interaction.partnerId) {
                HStack(spacing: Spacing.s) {
                    (Text(subject) + Text(" + ").foregroundStyle(Palette.cocoa) + Text(interaction.partnerDisplayName))
                        .headlineStyle(Typography.pairName)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Palette.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let description = interaction.description, !description.isEmpty {
                Text(description)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = interaction.evidenceURL {
                Link(destination: url) {
                    HStack(spacing: Spacing.xs) {
                        Text(interaction.sourceCitation ?? "PubMed").font(Typography.metaBold).underline()
                        Image(systemName: "arrow.up.right").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Palette.accentText)
                }
                .frame(minHeight: Metrics.touchTarget - 12)
                .accessibilityLabel("Open evidence \(interaction.sourceCitation ?? "") on PubMed")
            } else if let citation = interaction.sourceCitation, !citation.isEmpty {
                Text(citation).font(Typography.meta).foregroundStyle(Palette.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .padding(.bottom, Spacing.s)
    }
}

struct ExternalLinkRow: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack {
                Text(title)
                    .font(Typography.control)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.cocoa)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: Metrics.touchTarget + 8)
            .overlay(alignment: .bottom) { Rule().padding(.leading, Spacing.m) }
        }
        .accessibilityLabel("Open \(title) in the browser")
    }
}

#Preview {
    NavigationStack {
        IngredientDetailView(id: 6)
            .environment(\.api, MockAPIClient())
    }
}
