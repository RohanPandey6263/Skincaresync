import Foundation
import Testing
@testable import SkincareSync

struct RoutineTests {
    @Test func ingredientCountingMatchesTheParser() {
        #expect(IngredientCounter.count("") == 0)
        #expect(IngredientCounter.count("Ingredients: Water, Glycerin") == 2)
        #expect(IngredientCounter.count("Aqua (Water, Eau), Glycerin") == 2)
        #expect(IngredientCounter.count("Water,, Glycerin, ") == 2)
        #expect(IngredientCounter.count("INCI: Retinol") == 1)
    }

    @Test func readinessRequiresTwoReadyProducts() {
        var draft = RoutineDraft()
        var readiness = RoutineReadiness(draft: draft)
        #expect(!readiness.canAnalyze)
        #expect(readiness.explanation?.contains("0 of 2 ready") == true)

        draft.am.append(RoutineProduct(name: "Serum", rawIngredientList: "Water, Niacinamide"))
        readiness = RoutineReadiness(draft: draft)
        #expect(readiness.readyCount == 1)
        #expect(!readiness.canAnalyze)

        draft.pm.append(RoutineProduct(name: "Cream"))
        readiness = RoutineReadiness(draft: draft)
        #expect(!readiness.canAnalyze)
        #expect(readiness.explanation?.contains("Cream in Evening needs an ingredient list") == true)

        draft.pm[0].rawIngredientList = "Water, Retinol"
        readiness = RoutineReadiness(draft: draft)
        #expect(readiness.canAnalyze)
        #expect(readiness.explanation == nil)

        draft.am.append(RoutineProduct())
        readiness = RoutineReadiness(draft: draft)
        #expect(readiness.canAnalyze)
        #expect(readiness.explanation == "1 product without an ingredient list will be skipped.")
    }

    @Test func requestMappingSendsOnlyReadyProducts() {
        var draft = RoutineDraft()
        draft.profile = SkinProfile(skinType: .sensitive, concerns: [.rosacea, .antiAging])
        draft.am = [
            RoutineProduct(brand: " CeraVe ", name: " Cleanser ", rawIngredientList: " Water, Glycerin "),
            RoutineProduct(name: "Incomplete"),
        ]
        draft.pm = [RoutineProduct(name: "Night", rawIngredientList: "Retinol")]
        let request = AnalyzeRequest(draft: draft)
        #expect(request.skinProfile.skinType == "sensitive")
        #expect(request.skinProfile.concerns == ["rosacea", "anti-aging"])
        #expect(request.amProducts == [.init(brand: "CeraVe", name: "Cleanser", rawIngredientList: "Water, Glycerin")])
        #expect(request.pmProducts == [.init(brand: "", name: "Night", rawIngredientList: "Retinol")])
    }

    @Test func applyingAMatchKeepsRowIdentity() {
        var product = RoutineProduct(name: "typed name")
        let id = product.id
        product.apply(Fixtures.productSearch[0])
        #expect(product.id == id)
        #expect(product.name == "Hydrating Cleanser")
        #expect(product.code == "3337875597180")
        #expect(product.isReady)
        #expect(product.ingredientCount == 22)
    }

    @Test func draftRoundTripsThroughTheFileStore() throws {
        let directory = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileDraftStore(fileURL: directory.appending(path: "draft.json"))
        #expect(try store.load() == nil)

        let draft = Fixtures.sampleDraft
        try store.save(draft)
        #expect(try store.load() == draft)

        // A second store on the same file sees the same data, as after relaunch.
        let reopened = FileDraftStore(fileURL: store.fileURL)
        #expect(try reopened.load() == draft)

        try store.clear()
        #expect(try store.load() == nil)
    }

    @MainActor
    @Test func storeLoadsPersistedDraftAndSavesChanges() async throws {
        let persisted = InMemoryDraftStore(initial: Fixtures.sampleDraft)
        let store = RoutineStore(api: MockAPIClient(), draftStore: persisted)
        #expect(store.draft == Fixtures.sampleDraft)

        store.setSkinType(.dry)
        store.setConcern(.eczema, selected: true)
        let added = store.addProduct(to: .pm)
        store.updateProduct(RoutineProduct(id: added.id, name: "Toner", rawIngredientList: "Water"), in: .pm)
        store.saveNow()
        let saved = try #require(try persisted.load())
        #expect(saved.profile.skinType == .dry)
        #expect(saved.profile.concerns.contains(.eczema))
        #expect(saved.pm.last?.name == "Toner")

        store.removeProduct(id: added.id, in: .pm)
        store.moveProducts(from: IndexSet(integer: 0), to: 2, in: .am)
        store.saveNow()
        let moved = try #require(try persisted.load())
        #expect(moved.am.first?.name == "Niacinamide Serum")
        #expect(moved.pm.count == 2)
    }
}
