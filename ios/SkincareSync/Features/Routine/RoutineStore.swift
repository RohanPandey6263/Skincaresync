import Foundation
import Observation
import SwiftUI

/// Owns the routine draft, persists it, and runs the analysis. Shared by the
/// Routine tab and the Report screen.
@MainActor
@Observable
final class RoutineStore {
    enum AnalysisState: Equatable {
        case idle
        case running
        case failed(APIError)
    }

    private let api: any APIClient
    private let draftStore: any DraftStore

    private(set) var draft: RoutineDraft
    private(set) var report: AnalysisReport?
    private(set) var analysisState: AnalysisState = .idle
    /// Set when the persisted draft could not be read or written.
    private(set) var persistenceNotice: String?

    private var saveTask: Task<Void, Never>?
    private var analysisTask: Task<Bool, Never>?

    init(api: any APIClient, draftStore: any DraftStore) {
        self.api = api
        self.draftStore = draftStore
        do {
            draft = try draftStore.load() ?? .empty
        } catch {
            draft = .empty
            persistenceNotice = "Your saved routine could not be read, so a fresh one was started."
        }
    }

    var readiness: RoutineReadiness { RoutineReadiness(draft: draft) }
    var isAnalyzing: Bool { analysisState == .running }

    // MARK: Profile

    func setSkinType(_ type: SkinType) {
        draft.profile.skinType = type
        scheduleSave()
    }

    func setConcern(_ concern: Concern, selected: Bool) {
        var concerns = draft.profile.concerns
        if selected {
            if !concerns.contains(concern) { concerns.append(concern) }
        } else {
            concerns.removeAll { $0 == concern }
        }
        draft.profile.concerns = Concern.allCases.filter { concerns.contains($0) }
        scheduleSave()
    }

    // MARK: Products

    @discardableResult
    func addProduct(to slot: RoutineSlot, _ product: RoutineProduct = RoutineProduct()) -> RoutineProduct {
        draft[slot].append(product)
        scheduleSave()
        return product
    }

    func product(id: UUID, in slot: RoutineSlot) -> RoutineProduct? {
        draft[slot].first { $0.id == id }
    }

    func updateProduct(_ product: RoutineProduct, in slot: RoutineSlot) {
        guard let index = draft[slot].firstIndex(where: { $0.id == product.id }) else { return }
        if draft[slot][index] != product {
            draft[slot][index] = product
            scheduleSave()
        }
    }

    func removeProduct(id: UUID, in slot: RoutineSlot) {
        draft[slot].removeAll { $0.id == id }
        scheduleSave()
    }

    func removeProducts(at offsets: IndexSet, in slot: RoutineSlot) {
        draft[slot].remove(atOffsets: offsets)
        scheduleSave()
    }

    func moveProducts(from source: IndexSet, to destination: Int, in slot: RoutineSlot) {
        draft[slot].move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    /// Two-way binding onto one product, for the editor sheet.
    func binding(for id: UUID, in slot: RoutineSlot) -> Binding<RoutineProduct> {
        Binding(
            get: { [weak self] in self?.product(id: id, in: slot) ?? RoutineProduct(id: id) },
            set: { [weak self] in self?.updateProduct($0, in: slot) }
        )
    }

    func clearDraft() {
        draft = .empty
        report = nil
        analysisState = .idle
        scheduleSave()
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            try draftStore.save(draft)
        } catch {
            persistenceNotice = "Your routine could not be saved on this device."
        }
    }

    // MARK: Analysis

    /// Submits the routine. Returns true when a report is ready. A second call
    /// while one is in flight simply awaits the first, so a double tap cannot
    /// submit twice.
    @discardableResult
    func analyze() async -> Bool {
        if let analysisTask {
            return await analysisTask.value
        }
        guard readiness.canAnalyze else { return false }
        analysisState = .running
        let request = AnalyzeRequest(draft: draft)
        let profile = draft.profile
        let task = Task<Bool, Never> { [api] in
            do {
                let result = try await api.analyze(request)
                report = AnalysisReport(result: result, profile: profile, generatedAt: Date())
                analysisState = .idle
                Haptics.success()
                return true
            } catch let error as APIError {
                analysisState = error.isCancellation ? .idle : .failed(error)
                if !error.isCancellation { Haptics.warning() }
                return false
            } catch {
                analysisState = .failed(.invalidResponse)
                return false
            }
        }
        analysisTask = task
        let outcome = await task.value
        analysisTask = nil
        return outcome
    }

    func dismissAnalysisError() {
        if case .failed = analysisState { analysisState = .idle }
    }

    #if DEBUG
    /// Debug-only: seeds a report for screenshots and previews.
    func installFixtureReport(_ fixture: AnalysisReport) {
        report = fixture
    }
    #endif
}
