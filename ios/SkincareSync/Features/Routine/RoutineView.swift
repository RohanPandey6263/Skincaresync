import SwiftUI

enum RoutineRoute: Hashable {
    case report
}

struct RoutineView: View {
    @Environment(RoutineStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @State private var path: [RoutineRoute] = []
    @State private var editing: EditingProduct?
    @State private var editMode: EditMode = .inactive

    private struct EditingProduct: Identifiable {
        let id: UUID
        let slot: RoutineSlot
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let notice = store.persistenceNotice {
                    InlineNotice(kind: .info, text: notice)
                        .padding(Spacing.m)
                        .swissRow()
                }
                SkinProfileSection()
                ForEach(RoutineSlot.allCases) { slot in
                    slotSection(slot)
                }
                if store.report != nil {
                    PushRow(value: RoutineRoute.report) {
                        HStack {
                            Text("View last report")
                                .font(Typography.control)
                                .textCase(.uppercase)
                                .kerning(Typography.labelTracking)
                            Spacer()
                            Image(systemName: "arrow.right").font(.body.weight(.bold))
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(Spacing.m)
                        .frame(minHeight: Metrics.touchTarget + 8)
                    }
                    .swissRow()
                    Rule().swissRow()
                }
                Color.clear.frame(height: Spacing.xl).swissRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.page)
            .environment(\.editMode, $editMode)
            .environment(\.defaultMinListRowHeight, 1)
            .navigationTitle("Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.draft.allProducts.isEmpty {
                        Button(editMode.isEditing ? "Done" : "Reorder") {
                            withAnimation(.linear(duration: 0.15)) { editMode = editMode.isEditing ? .inactive : .active }
                        }
                        .font(Typography.control)
                        .textCase(.uppercase)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AnalyzeBar(onAnalyzed: { path.append(.report) })
            }
            .navigationDestination(for: RoutineRoute.self) { route in
                switch route {
                case .report:
                    if let report = store.report {
                        ReportView(report: report)
                    } else {
                        EmptyStateView(symbol: "doc.text", title: "No report yet",
                                       message: "Analyze your routine to see conflicts, cautions and synergies.")
                    }
                }
            }
            .sheet(item: $editing) { item in
                ProductEditorView(product: store.binding(for: item.id, in: item.slot), slot: item.slot) {
                    store.removeProduct(id: item.id, in: item.slot)
                }
            }
            .onAppear {
                if navigation.openReportOnLaunch, store.report != nil, path.isEmpty {
                    navigation.openReportOnLaunch = false
                    path.append(.report)
                }
                if navigation.openEditorOnLaunch, let first = store.draft.am.first {
                    navigation.openEditorOnLaunch = false
                    editing = EditingProduct(id: first.id, slot: .am)
                }
            }
        }
    }

    @ViewBuilder
    private func slotSection(_ slot: RoutineSlot) -> some View {
        SectionHeaderRow(
            number: slot == .am ? "02" : "03",
            eyebrow: slot.title,
            title: "\(slot.title) routine",
            description: store.draft[slot].isEmpty ? "No \(slot.title.lowercased()) products yet." : nil,
            trailing: AnyView(
                Image(systemName: slot.symbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 48, height: 48)
                    .overlay(Rectangle().strokeBorder(Palette.border, lineWidth: Metrics.border))
                    .accessibilityHidden(true)
            )
        )
        .swissRow()

        ForEach(Array(store.draft[slot].enumerated()), id: \.element.id) { index, product in
            Button {
                editing = EditingProduct(id: product.id, slot: slot)
            } label: {
                ProductRow(product: product, position: index + 1)
            }
            .buttonStyle(.plain)
            .swissRow()
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    store.removeProduct(id: product.id, in: slot)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .tint(Palette.accent)
            }
            .contextMenu {
                Button { editing = EditingProduct(id: product.id, slot: slot) } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) { store.removeProduct(id: product.id, in: slot) } label: { Label("Remove", systemImage: "trash") }
            }
            .accessibilityHint("Opens the product editor")
        }
        .onDelete { store.removeProducts(at: $0, in: slot) }
        .onMove { store.moveProducts(from: $0, to: $1, in: slot) }

        Button {
            let product = store.addProduct(to: slot)
            editing = EditingProduct(id: product.id, slot: slot)
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: "plus").font(.body.weight(.bold))
                Text("Add product")
            }
            .font(Typography.control)
            .textCase(.uppercase)
            .kerning(Typography.labelTracking)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Spacing.m)
            .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget + 8, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add product to \(slot.title.lowercased()) routine")
        .swissRow()
        Rule().swissRow()
    }
}

/// One product in the routine list: an index numeral, the name, and a status
/// line that says "ready" or "needs an ingredient list" in words.
struct ProductRow: View {
    let product: RoutineProduct
    var position: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Spacing.m) {
                Text(String(format: "%02d", position))
                    .font(Typography.numeral)
                    .foregroundStyle(product.isReady ? Palette.ink.opacity(0.15) : Palette.accent.opacity(0.7))
                    .frame(width: 60, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(product.trimmedName.isEmpty ? "New product" : product.trimmedName)
                        .headlineStyle(Typography.pairName, color: product.trimmedName.isEmpty ? Palette.secondary : Palette.ink)
                        .lineLimit(2)
                    if !product.trimmedBrand.isEmpty {
                        Text(product.trimmedBrand)
                            .font(Typography.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                    HStack(spacing: Spacing.xs) {
                        Rectangle()
                            .fill(product.isReady ? Palette.ink : Palette.accent)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(statusText)
                            .font(Typography.metaBold)
                            .foregroundStyle(product.isReady ? Palette.ink : Palette.accentText)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.m)
            .frame(minHeight: Metrics.touchTarget + 16)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            Rule()
        }
        .background(Palette.page)
    }

    private var statusText: String {
        if product.isReady {
            let count = product.ingredientCount
            return "\(count) ingredient\(count == 1 ? "" : "s") ready"
        }
        if product.trimmedName.isEmpty { return "Needs a name and an ingredient list" }
        return "Needs an ingredient list"
    }
}

/// Bottom action bar: a black band. The count, the reason, and the one red action.
private struct AnalyzeBar: View {
    @Environment(RoutineStore.self) private var store
    let onAnalyzed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if case .failed(let error) = store.analysisState {
                InlineNotice(kind: .error, text: "\(error.title). \(error.message)", actionTitle: "Dismiss") {
                    store.dismissAnalysisError()
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    Text(String(format: "%02d", store.readiness.readyCount))
                        .font(Typography.numeral)
                        .foregroundStyle(Palette.onInk)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.readiness.readyCount == 1 ? "product ready" : "products ready")
                            .eyebrowStyle(color: Palette.onInk)
                        if let explanation = store.readiness.explanation {
                            Text(explanation)
                                .font(Typography.meta)
                                .foregroundStyle(store.readiness.canAnalyze ? Palette.onInk.opacity(0.7) : Palette.onInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(store.readiness.readyCount) products ready. \(store.readiness.explanation ?? "")")
            }
            Button {
                Task {
                    if await store.analyze() { onAnalyzed() }
                }
            } label: {
                HStack(spacing: Spacing.s) {
                    if store.isAnalyzing {
                        ProgressView().tint(Palette.onAccent)
                    }
                    Text(store.isAnalyzing ? "Analyzing…" : "Analyze routine")
                    Spacer()
                    Image(systemName: "arrow.right").font(.body.weight(.bold))
                }
            }
            .buttonStyle(.accent)
            .disabled(!store.readiness.canAnalyze || store.isAnalyzing)
            .accessibilityHint(store.readiness.explanation ?? "Checks the products for conflicts, cautions and synergies")
        }
        .padding(Spacing.m)
        .background(Palette.ink)
        .overlay(alignment: .top) { Rectangle().fill(Palette.ink).frame(height: Metrics.borderHeavy) }
    }
}

#Preview("Sample draft") {
    RoutineView()
        .environment(\.api, MockAPIClient())
        .environment(RoutineStore(api: MockAPIClient(), draftStore: InMemoryDraftStore(initial: Fixtures.sampleDraft)))
        .environment(AppNavigation())
}

#Preview("Empty") {
    RoutineView()
        .environment(\.api, MockAPIClient())
        .environment(RoutineStore(api: MockAPIClient(), draftStore: InMemoryDraftStore()))
        .environment(AppNavigation())
}
