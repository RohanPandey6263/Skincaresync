import Foundation
import Testing
@testable import SkincareSync

struct DecodingTests {
    private let decoder = APICoding.decoder

    @Test func healthDecodes() throws {
        let health = try decoder.decode(HealthStatus.self, from: TestSupport.fixture("health"))
        #expect(health.ok)
        #expect(health.database == "ok")
        #expect(health.ingredientCount == 22288)
        #expect(health.productCount == 3549)
        #expect(health.interactionCount == 156)
    }

    @Test func unavailableHealthDecodesWithNullCounts() throws {
        let body = Data(#"{"ok":false,"database":"unavailable","ingredient_count":null,"product_count":null,"interaction_count":null}"#.utf8)
        let health = try decoder.decode(HealthStatus.self, from: body)
        #expect(!health.ok)
        #expect(health.ingredientCount == nil)
        #expect(HomeViewModel.statusLine(for: health) == nil)
    }

    @Test func productSearchDecodes() throws {
        let products = try decoder.decode([ProductMatch].self, from: TestSupport.fixture("product_search"))
        let first = try #require(products.first)
        #expect(first.brand == "CeraVe")
        #expect(first.name == "Hydrating Cleanser")
        #expect(first.code == "3337875597180")
        #expect(first.similarityScore == 100)
        #expect(first.rawIngredientList.hasPrefix("aqua/water"))
        #expect(first.imageUrl?.hasPrefix("https://") == true)
        #expect(first.sourceLabel == "Open Beauty Facts")
        #expect(first.ndc == nil)
    }

    @Test func ingredientDetailDecodes() throws {
        let detail = try decoder.decode(IngredientDetail.self, from: TestSupport.fixture("ingredient_detail"))
        #expect(detail.id == 6)
        #expect(detail.displayName == "Retinol")
        #expect(detail.isCurated)
        #expect(detail.isInEngine)
        #expect(!detail.isRestricted)
        #expect(detail.primaryCAS == "68-26-8")
        #expect(detail.phMin == 5.5)
        #expect(detail.comodogenic == 2)
        #expect(detail.interactions.count == detail.interactionCount)
        let first = try #require(detail.interactions.first)
        #expect(first.interactionType == .conflict)
        #expect(first.severity == .high)
        #expect(first.partnerDisplayName == "Glycolic Acid")
        #expect(first.evidenceURL?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/33377285/")
        #expect(detail.related.isEmpty == false)
        #expect(detail.openBeautyFactsURL?.absoluteString == "https://world.openbeautyfacts.org/ingredient/retinol")
        #expect(detail.wikidataURL?.absoluteString == "https://www.wikidata.org/wiki/Q424976")
        #expect(detail.aliases.count <= 24)
    }

    @Test func ingredientSearchPageAndFacetsDecode() throws {
        let page = try decoder.decode(IngredientSearchPage.self, from: TestSupport.fixture("ingredient_search"))
        #expect(page.items.count == 5)
        #expect(page.limit == 5)
        #expect(page.hasMore)
        #expect(page.items.first?.displayName == "Retinol")
        let facets = try decoder.decode(CatalogFacets.self, from: TestSupport.fixture("ingredient_facets"))
        #expect(facets.functions.first?.value == "skin-conditioning")
        #expect(facets.letters.contains { $0.letter == "#" })
        #expect(facets.stats.total > 0)
        let suggestions = try decoder.decode([IngredientSuggestion].self, from: TestSupport.fixture("ingredient_suggest"))
        #expect(suggestions.first?.displayName == "Retinol")
    }

    @Test func analysisFixtureDecodesCompletely() throws {
        let result = try decoder.decode(AnalysisResult.self, from: TestSupport.fixture("analysis"))
        #expect(result.overallScore.status == .conflict)
        #expect(result.overallScore.high == 1)
        #expect(result.conflicts.count == 1)
        #expect(result.cautions.count == 7)
        #expect(result.synergies.count == 5)
        #expect(result.unknownPairCount == 56)
        #expect(result.unresolvedTokens.map(\.rawToken) == ["Unobtainium Extract"])
        #expect(result.parsedProducts.count == 5)

        let conflict = try #require(result.conflicts.first)
        #expect(conflict.interactionType == .conflict)
        #expect(conflict.severity == .high)
        #expect(conflict.scope == .direct)
        #expect(conflict.ingredientA.inciName == "Retinol")
        #expect(conflict.ingredientB.inciName == "Glycolic Acid")
        #expect(conflict.productA.label == "Example Retinol Night Cream")
        #expect(conflict.confidence == "provisional")
        #expect(conflict.evidenceURL?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/33377285/")

        let escalated = try #require(result.cautions.first { $0.wasEscalated })
        #expect(escalated.baseSeverity == .medium)
        #expect(escalated.severity == .high)
        #expect(result.cautions.contains { $0.scope == .cumulative })
        #expect(result.synergies.allSatisfy { $0.interactionType == .synergy })
        #expect(Set(result.conflicts.map(\.id)).count == result.conflicts.count)
    }

    @Test func unknownInteractionTypeDoesNotBreakDecoding() throws {
        let body = Data(#"{"interaction_id":1,"interaction_type":"novelty","severity":"low","base_severity":"low","skin_modifier_applied":false,"scope":"direct","mechanism":null,"description":null,"source_citation":null,"confidence":"low","ingredient_a":{"id":1,"inci_name":"A","synonyms":[],"category":null,"ph_min":null,"ph_max":null,"comodogenic":null,"alt_names":[]},"ingredient_b":{"id":2,"inci_name":"B","synonyms":[],"category":null,"ph_min":null,"ph_max":null,"comodogenic":null,"alt_names":[]},"product_a":{"name":"P","brand":"","raw_ingredient_list":"A","label":"P"},"product_b":{"name":"Q","brand":"","raw_ingredient_list":"B","label":"Q"}}"#.utf8)
        let finding = try decoder.decode(InteractionFinding.self, from: body)
        #expect(finding.interactionType == .unknown("novelty"))
        #expect(finding.evidenceURL == nil)
    }

    @Test func authSessionDecodesWithMicrosecondDates() throws {
        let session = try decoder.decode(AuthSession.self, from: TestSupport.fixture("auth_session"))
        #expect(session.user.email == "sample@example.com")
        #expect(session.csrfToken == "fixture-csrf-token-not-a-secret")
        #expect(!session.user.emailVerified)
        #expect(session.user.hasPassword)
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: session.user.createdAt)
        #expect(components.year == 2026 && components.month == 8 && components.day == 30 && components.hour == 18)
    }

    @Test func sessionsEventsAndIdentitiesDecode() throws {
        let sessions = try decoder.decode([SessionInfo].self, from: TestSupport.fixture("auth_sessions"))
        #expect(sessions.count == 2)
        #expect(sessions[0].current)
        #expect(sessions[1].ipAddress == "203.0.113.9")
        let events = try decoder.decode([AuthEvent].self, from: TestSupport.fixture("auth_events"))
        #expect(events.count == 3)
        #expect(events[1].title == "Password changed")
        #expect(events[1].detail["sessions_revoked"] == .number(1))
        #expect(events[2].ipAddress == nil)
        let identities = try decoder.decode([LinkedIdentity].self, from: TestSupport.fixture("auth_identities"))
        #expect(identities.first?.providerLabel == "Google")
        #expect(identities.first?.lastLoginAt == nil)
        let providers = try decoder.decode([OAuthProvider].self, from: Data(#"[{"key":"google","display_name":"Google"}]"#.utf8))
        #expect(providers.first?.displayName == "Google")
    }

    @Test func dateParsingHandlesEveryBackendShape() {
        for text in ["2026-09-01T09:12:03.000120+00:00", "2026-09-01T09:12:03.5Z", "2026-09-01T09:12:03Z", "2026-09-01T09:12:03.123456789Z", "2026-09-01T09:12:03"] {
            #expect(APIDates.parse(text) != nil, "failed: \(text)")
        }
        #expect(APIDates.parse("yesterday") == nil)
    }

    @Test func nullSessionIsRecognised() {
        #expect(LiveAPIClient.isJSONNull(Data("null".utf8)))
    }
}
