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
                        .cardGutter()
                        .padding(.top, Spacing.m)
                        .swissRow()
                }
                SkinProfileSection()
                ForEach(RoutineSlot.allCases) { slot in
                    slotSection(slot)
                }
                if store.report != nil {
                    PushRow(value: RoutineRoute.report) {
                        HStack(spacing: Spacing.m) {
                            IconBox(symbol: "doc.text.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("View last report").headlineStyle(Typography.pairName)
                                Text("The findings from your most recent analysis")
                                    .font(Typography.meta)
                                    .foregroundStyle(Palette.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Palette.faint)
                        }
                        .padding(Spacing.m)
                        .softCard()
                        .cardGutter()
                        .padding(.top, Spacing.l)
                    }
                    .swissRow()
                }
                Color.clear.frame(height: Spacing.xxl).swissRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.page)
            .environment(\.editMode, $editMode)
            .environment(\.defaultMinListRowHeight, 1)
            .navigationTitle("Routine")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.draft.allProducts.isEmpty {
                        Button(editMode.isEditing ? "Done" : "Reorder") {
                            withAnimation(.easeOut(duration: 0.2)) { editMode = editMode.isEditing ? .inactive : .active }
                        }
                        .font(Typography.control)
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.cocoa)
                    .frame(width: 48, height: 48)
                    .background(Palette.muted, in: Circle())
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
        }
        .buttonStyle(.secondary)
        .accessibilityLabel("Add product to \(slot.title.lowercased()) routine")
        .cardGutter()
        .padding(.top, Spacing.xs)
        .swissRow()
    }
}

/// One product in the routine: a round index, the name, and a status line that
/// says "ready" or "needs an ingredient list" in words. A card, not a row.
struct ProductRow: View {
    let product: RoutineProduct
    var position: Int = 1

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Text(String(format: "%02d", position))
                .font(Typography.metaBold)
                .foregroundStyle(product.isReady ? Palette.cocoa : Palette.accentText)
                .frame(width: 38, height: 38)
                .background(product.isReady ? Palette.muted : Palette.wash(Palette.accent), in: Circle())
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
                HStack(spacing: Spacing.xs + 2) {
                    StatusDot(color: product.isReady ? Palette.mint : Palette.accent)
                    Text(statusText)
                        .font(Typography.metaBold)
                        .foregroundStyle(product.isReady ? Palette.secondary : Palette.accentText)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.faint)
                .accessibilityHidden(true)
        }
        .padding(Spacing.m)
        .frame(minHeight: Metrics.touchTarget + 24)
        .softCard(radius: Radius.tile)
        .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .cardGutter()
        .padding(.bottom, Spacing.s)
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

/// Bottom action bar: a card that floats over the list. The count, the reason,
/// and the one coral action.
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
                HStack(spacing: Spacing.m) {
                    Text("\(store.readiness.readyCount)")
                        .font(Typography.numeral)
                        .foregroundStyle(Palette.ink)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.readiness.readyCount == 1 ? "product ready" : "products ready")
                            .eyebrowStyle(color: Palette.secondary)
                        if let explanation = store.readiness.explanation {
                            Text(explanation)
                                .font(Typography.meta)
                                .foregroundStyle(store.readiness.canAnalyze ? Palette.faint : Palette.accentText)
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
                }
            }
            .buttonStyle(.accent)
            .disabled(!store.readiness.canAnalyze || store.isAnalyzing)
            .accessibilityHint(store.readiness.explanation ?? "Checks the products for conflicts, cautions and synergies")
        }
        .padding(Spacing.l)
        .softCard()
        .cardGutter()
        .padding(.bottom, Spacing.s)
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
