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
                    Section {
                        InlineNotice(kind: .info, text: notice)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                SkinProfileSection()
                ForEach(RoutineSlot.allCases) { slot in
                    slotSection(slot)
                }
                if store.report != nil {
                    Section {
                        NavigationLink(value: RoutineRoute.report) {
                            Label("View last report", systemImage: "doc.text.magnifyingglass")
                                .foregroundStyle(Palette.forest)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.page)
            .environment(\.editMode, $editMode)
            .navigationTitle("Routine")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.draft.allProducts.isEmpty {
                        Button(editMode.isEditing ? "Done" : "Reorder") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
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

    private func slotSection(_ slot: RoutineSlot) -> some View {
        Section {
            ForEach(store.draft[slot]) { product in
                Button {
                    editing = EditingProduct(id: product.id, slot: slot)
                } label: {
                    ProductRow(product: product)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        store.removeProduct(id: product.id, in: slot)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
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
                Label("Add product", systemImage: "plus.circle")
                    .foregroundStyle(Palette.sageText)
                    .frame(minHeight: Metrics.touchTarget - 12)
            }
            .accessibilityLabel("Add product to \(slot.title.lowercased()) routine")
        } header: {
            Label(slot.title, systemImage: slot.symbol)
                .font(Typography.heading)
                .foregroundStyle(Palette.forest)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            if store.draft[slot].isEmpty {
                Text("No \(slot.title.lowercased()) products yet.")
            }
        }
    }
}

/// One product in the routine list: name, brand, and a status line that reads
/// "ready" or "needs an ingredient list" in words, not just colour.
struct ProductRow: View {
    let product: RoutineProduct

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(product.trimmedName.isEmpty ? "New product" : product.trimmedName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(product.trimmedName.isEmpty ? Palette.muted : Palette.forest)
                if !product.trimmedBrand.isEmpty {
                    Text(product.trimmedBrand)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.muted)
                }
                HStack(spacing: Spacing.xs) {
                    Image(systemName: product.isReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(product.isReady ? Palette.sage : Palette.terracotta)
                        .accessibilityHidden(true)
                    Text(statusText)
                        .font(Typography.meta)
                        .foregroundStyle(product.isReady ? Palette.sageText : Palette.terracottaText)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.faint)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Metrics.touchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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

/// Bottom action bar: the analyze button plus a plain-language reason when
/// the routine is not ready yet. The button is never silently disabled.
private struct AnalyzeBar: View {
    @Environment(RoutineStore.self) private var store
    let onAnalyzed: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s) {
            if case .failed(let error) = store.analysisState {
                InlineNotice(kind: .error, text: "\(error.title). \(error.message)", actionTitle: "Dismiss") {
                    store.dismissAnalysisError()
                }
            } else if let explanation = store.readiness.explanation {
                Text(explanation)
                    .font(Typography.meta)
                    .foregroundStyle(store.readiness.canAnalyze ? Palette.muted : Palette.terracottaText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            Button {
                Task {
                    if await store.analyze() { onAnalyzed() }
                }
            } label: {
                HStack(spacing: Spacing.s) {
                    if store.isAnalyzing {
                        ProgressView().tint(Palette.onForest)
                    }
                    Text(store.isAnalyzing ? "Analyzing…" : "Analyze routine")
                }
            }
            .buttonStyle(.primary)
            .disabled(!store.readiness.canAnalyze || store.isAnalyzing)
            .accessibilityHint(store.readiness.explanation ?? "Checks the products for conflicts, cautions and synergies")
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.s)
        .background(.bar)
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
