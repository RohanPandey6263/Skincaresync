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
                List { SkeletonRows(count: 6) }
                    .listStyle(.plain)
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

private struct IngredientDetailContent: View {
    let detail: IngredientDetail

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(detail.displayName)
                        .font(Typography.title)
                        .foregroundStyle(Palette.forest)
                        .accessibilityAddTraits(.isHeader)
                    if detail.inciName != detail.displayName {
                        Text(detail.inciName)
                            .font(Typography.meta)
                            .foregroundStyle(Palette.muted)
                            .textSelection(.enabled)
                    }
                    if detail.isCurated || detail.isInEngine || detail.isRestricted {
                        FlowLayout(spacing: Spacing.xs) {
                            if detail.isCurated { TagPill(text: "Curated", symbol: "checkmark.seal") }
                            if detail.isInEngine { TagPill(text: "In compatibility engine", symbol: "link", tone: ReportSectionKind.synergies.presentation) }
                            if detail.isRestricted { TagPill(text: "Restricted", symbol: "exclamationmark.triangle", tone: Severity.medium.presentation) }
                        }
                    }
                    if let description = detail.description, !description.isEmpty {
                        Text(description)
                            .font(Typography.body)
                            .foregroundStyle(Palette.forest)
                            .padding(.top, Spacing.xs)
                    }
                    if let restriction = detail.restriction, !restriction.isEmpty {
                        InlineNotice(kind: .info, text: restriction)
                            .padding(.top, Spacing.xs)
                    }
                }
                .padding(.vertical, Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
            }

            Section("Details") {
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

            if !detail.functions.isEmpty {
                Section("Functions") {
                    FlowLayout(spacing: Spacing.xs) {
                        ForEach(detail.functions, id: \.self) { function in
                            TagPill(text: IngredientFormatting.functionLabel(function))
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Functions: \(detail.functions.map(IngredientFormatting.functionLabel).joined(separator: ", "))")
                }
            }

            if !detail.aliases.isEmpty {
                Section("Also known as") {
                    Text(detail.aliases.joined(separator: " · "))
                        .font(Typography.body)
                        .foregroundStyle(Palette.muted)
                        .textSelection(.enabled)
                }
            }

            if !detail.interactions.isEmpty {
                Section {
                    ForEach(detail.interactions) { interaction in
                        InteractionRow(subject: detail.displayName, interaction: interaction)
                    }
                } header: {
                    Text("Known interactions (\(detail.interactions.count))")
                } footer: {
                    Text("Severity shown is the rule's base level; your skin profile can raise it in a report.")
                }
            }

            if !detail.related.isEmpty {
                Section("Related ingredients") {
                    ForEach(detail.related) { related in
                        NavigationLink(value: related.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(related.displayName).foregroundStyle(Palette.forest)
                                if let category = related.category {
                                    Text(IngredientFormatting.functionLabel(category)).font(Typography.meta).foregroundStyle(Palette.muted)
                                }
                            }
                            .frame(minHeight: Metrics.touchTarget - 12)
                        }
                    }
                }
            }

            if detail.pubChemURL != nil || detail.wikidataURL != nil || detail.openBeautyFactsURL != nil {
                Section("External references") {
                    if let url = detail.pubChemURL { ExternalLinkRow(title: "PubChem", url: url) }
                    if let url = detail.wikidataURL { ExternalLinkRow(title: "Wikidata", url: url) }
                    if let url = detail.openBeautyFactsURL { ExternalLinkRow(title: "Open Beauty Facts", url: url) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
            HStack {
                TagPill(text: badgeText, symbol: tone.symbol, tone: tone)
                Spacer()
            }
            NavigationLink(value: interaction.partnerId) {
                Text("\(subject) + \(interaction.partnerDisplayName)")
                    .font(Typography.pairName)
                    .foregroundStyle(Palette.forest)
            }
            if let description = interaction.description, !description.isEmpty {
                Text(description)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = interaction.evidenceURL {
                Link(destination: url) {
                    Label(interaction.sourceCitation ?? "PubMed", systemImage: "arrow.up.right.square")
                        .font(Typography.meta)
                        .foregroundStyle(Palette.terracottaText)
                }
                .frame(minHeight: Metrics.touchTarget - 12)
                .accessibilityLabel("Open evidence \(interaction.sourceCitation ?? "") on PubMed")
            } else if let citation = interaction.sourceCitation, !citation.isEmpty {
                Text(citation).font(Typography.meta).foregroundStyle(Palette.faint)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var badgeText: String {
        switch interaction.interactionType {
        case .synergy: "Synergy"
        case .conflict: "Conflict · \(interaction.severity.shortLabel)"
        case .caution: "Caution · \(interaction.severity.shortLabel)"
        case .redundant: "Redundant · \(interaction.severity.shortLabel)"
        case .unknown(let raw): "\(raw.capitalized) · \(interaction.severity.shortLabel)"
        }
    }
}

struct ExternalLinkRow: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack {
                Text(title).foregroundStyle(Palette.forest)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(Palette.terracottaText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Metrics.touchTarget - 12)
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
