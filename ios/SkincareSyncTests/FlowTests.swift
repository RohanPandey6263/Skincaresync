import Foundation
import Testing
@testable import SkincareSync

/// Mock-driven happy path: search, pick two products, analyze, read the report.
@MainActor
struct FlowTests {
    @Test func searchSelectAnalyzeProducesAReport() async throws {
        let api = MockAPIClient()
        let retinol = ProductMatch(code: "111", brand: "Example", name: "Retinol Night Cream",
                                   rawIngredientList: "Water, Retinol, Niacinamide", source: "catalog",
                                   imageUrl: nil, productUrl: nil, similarityScore: 96, ndc: nil, setid: nil,
                                   searchAliases: [], brandSimilarityScore: 100, nameSimilarityScore: 95)
        api.searchProductsHandler = { input in
            input.name.lowercased().contains("retinol") ? [retinol] : Fixtures.productSearch
        }

        let store = RoutineStore(api: api, draftStore: InMemoryDraftStore())
        store.setSkinType(.sensitive)
        store.setConcern(.rosacea, selected: true)

        // Morning: search for the cleanser and pick the first match.
        let editor = ProductEditorViewModel(api: api)
        let am = store.addProduct(to: .am)
        editor.searchProducts(brand: "CeraVe", name: "Hydrating Cleanser")
        #expect(await TestSupport.waitUntil { editor.search != .loading })
        guard case .results(let matches) = editor.search else {
            Issue.record("expected results, got \(editor.search)")
            return
        }
        var amProduct = try #require(store.product(id: am.id, in: .am))
        let amMatch = try #require(matches.first)
        amProduct.apply(amMatch)
        store.updateProduct(amProduct, in: .am)
        #expect(!store.readiness.canAnalyze)

        // Evening: a second search returns the retinol cream.
        let pm = store.addProduct(to: .pm)
        editor.searchProducts(brand: "", name: "retinol")
        #expect(await TestSupport.waitUntil { editor.search != .loading })
        guard case .results(let pmMatches) = editor.search else {
            Issue.record("expected results, got \(editor.search)")
            return
        }
        var pmProduct = try #require(store.product(id: pm.id, in: .pm))
        let pmMatch = try #require(pmMatches.first)
        pmProduct.apply(pmMatch)
        store.updateProduct(pmProduct, in: .pm)
        #expect(store.readiness.canAnalyze)

        let succeeded = await store.analyze()
        #expect(succeeded)
        #expect(store.analysisState == .idle)
        let report = try #require(store.report)
        #expect(report.profile.skinType == .sensitive)

        let sent = try #require(api.recorded.analyzeRequests.first)
        #expect(sent.skinProfile.skinType == "sensitive")
        #expect(sent.skinProfile.concerns == ["rosacea"])
        #expect(sent.amProducts.map(\.name) == ["Hydrating Cleanser"])
        #expect(sent.pmProducts.map(\.name) == ["Retinol Night Cream"])
        #expect(api.recorded.productSearches.count == 2)

        let presentation = ReportPresentation(result: report.result)
        #expect(presentation.sections.map(\.kind) == [.conflicts, .cautions, .synergies])
        #expect(presentation.sections[0].count == 1)
    }

    @Test func staleSearchResultsAreDropped() async throws {
        let api = MockAPIClient()
        api.searchProductsHandler = { input in
            if input.name == "slow" {
                try await Task.sleep(for: .milliseconds(300))
                return [Fixtures.productSearch[0]]
            }
            return []
        }
        let editor = ProductEditorViewModel(api: api)
        editor.searchProducts(brand: "", name: "slow")
        editor.searchProducts(brand: "", name: "fast")
        #expect(await TestSupport.waitUntil { editor.search == .empty })
        try await Task.sleep(for: .milliseconds(400))
        #expect(editor.search == .empty)
    }

    @Test func analysisFailureKeepsTheDraftAndReportsTheError() async throws {
        let api = MockAPIClient()
        api.analyzeHandler = { _ in throw APIError.server(status: 429, message: "Too many requests.", retryAfterSeconds: 3) }
        let store = RoutineStore(api: api, draftStore: InMemoryDraftStore(initial: Fixtures.sampleDraft))
        let before = store.draft
        #expect(await store.analyze() == false)
        #expect(store.draft == before)
        #expect(store.report == nil)
        guard case .failed(let error) = store.analysisState else {
            Issue.record("expected failure state")
            return
        }
        #expect(error.isRateLimited)
        store.dismissAnalysisError()
        #expect(store.analysisState == .idle)
    }

    @Test func duplicateSubmissionsShareOneRequest() async throws {
        let api = MockAPIClient()
        api.latency = .milliseconds(150)
        let store = RoutineStore(api: api, draftStore: InMemoryDraftStore(initial: Fixtures.sampleDraft))
        async let first = store.analyze()
        async let second = store.analyze()
        let results = await [first, second]
        #expect(results == [true, true])
        #expect(api.recorded.analyzeRequests.count == 1)
    }

    @Test func ingredientBrowsingPaginatesAndSurvivesRefreshFailure() async throws {
        let api = MockAPIClient()
        let page = Fixtures.ingredientSearch
        api.searchIngredientsHandler = { query in
            if query.offset == 0 { return page }
            var next = page
            next.offset = query.offset
            next.hasMore = false
            next.items = page.items.map { item in
                var copy = item
                copy.id += 1000
                return copy
            }
            return next
        }
        let model = IngredientsViewModel(api: api)
        model.start()
        #expect(await TestSupport.waitUntil { model.phase == .loaded })
        #expect(model.items.count == 5)
        #expect(model.hasMore)

        model.loadNextPage()
        #expect(await TestSupport.waitUntil { model.loadMore == .idle && model.items.count == 10 })
        #expect(!model.hasMore)

        api.searchIngredientsHandler = { _ in throw APIError.offline }
        await model.refresh()
        #expect(model.items.count == 10)
        #expect(model.inlineError == .offline)
        #expect(model.phase == .loaded)
    }

    @Test func sessionBootstrapAndSignOut() async throws {
        let api = MockAPIClient()
        let store = SessionStore(api: api)
        await store.bootstrap()
        #expect(store.state == .signedOut)

        api.loginHandler = { _ in Fixtures.authSession }
        #expect(await store.signIn(email: "sample@example.com", password: "correct horse battery staple") == nil)
        #expect(store.user?.email == "sample@example.com")

        api.messageHandler = { _ in throw APIError.offline }
        await store.signOut()
        #expect(store.state == .signedOut)
        #expect(api.recorded.logoutCalls == 1)
        #expect(api.recorded.clearLocalSessionCalls == 1)
        #expect(store.notice?.contains("Signed out on this device") == true)
    }
}
