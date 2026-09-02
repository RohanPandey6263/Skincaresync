import Foundation
import Testing
@testable import SkincareSync

/// End-to-end check of cookies and CSRF against a running development backend.
///
/// Skipped unless the test bundle is compiled with the
/// `SKINCARESYNC_LIVE_TESTS` condition:
/// `xcodebuild test ... SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) SKINCARESYNC_LIVE_TESTS'`.
/// Registers a throwaway account, so run it against a development database only.
@Suite(.serialized)
struct LiveBackendTests {
    private static var enabled: Bool {
        #if SKINCARESYNC_LIVE_TESTS
        true
        #else
        false
        #endif
    }

    private static func client() throws -> LiveAPIClient {
        let raw = ProcessInfo.processInfo.environment["SKINCARESYNC_LIVE_BASE_URL"] ?? "http://127.0.0.1:8000"
        let configuration = try APIConfiguration.parse(raw, requireHTTPS: false).get()
        // A private cookie jar so the test never touches the app's session.
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieAcceptPolicy = .always
        sessionConfiguration.httpCookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "live-tests-\(UUID().uuidString)")
        return LiveAPIClient(configuration: configuration, session: URLSession(configuration: sessionConfiguration))
    }

    @Test(.enabled(if: enabled)) func catalogEndpointsAnswer() async throws {
        let api = try Self.client()
        let health = try await api.health()
        #expect(health.ok)
        #expect((health.ingredientCount ?? 0) > 0)

        let products = try await api.searchProducts(brand: "CeraVe", name: "Hydrating Cleanser")
        #expect(products.contains { $0.name.localizedCaseInsensitiveContains("hydrating") })

        let retinA = try await api.searchProducts(brand: "", name: "tretinoin")
        #expect(retinA.contains { $0.brand.localizedCaseInsensitiveContains("retin") })

        let facets = try await api.ingredientFacets()
        #expect(facets.stats.total > 0)
        let page = try await api.searchIngredients(IngredientQuery(text: "retinol", limit: 5))
        #expect(page.items.first?.displayName == "Retinol")
        let detail = try await api.ingredient(id: page.items[0].id)
        #expect(detail.interactions.count == detail.interactionCount)
        let suggestions = try await api.suggestIngredients("niacin")
        #expect(!suggestions.isEmpty)

        do {
            _ = try await api.lookupProduct(code: "0000000000000")
            Issue.record("expected a 404 for an unknown code")
        } catch let error as APIError {
            #expect(error.isNotFound || error.status == 502)
        }
    }

    @Test(.enabled(if: enabled)) func sessionCookieAndCSRFRoundTrip() async throws {
        let api = try Self.client()
        let initial = try await api.session()
        #expect(initial == nil)

        let email = "ios-live-\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "correct horse battery staple \(Int.random(in: 1000...9999))"
        let registered = try await api.register(email: email, password: password, displayName: "iOS live test")
        #expect(registered.message.contains("sent"))

        let login = try await api.login(email: email, password: password)
        #expect(login.user.email == email)
        #expect(!login.csrfToken.isEmpty)

        let session = try #require(try await api.session())
        #expect(session.user.userId == login.user.userId)
        let me = try await api.me()
        #expect(me.email == email)

        // A state-changing call while signed in must carry the CSRF token.
        let request = AnalyzeRequest(draft: Fixtures.sampleDraft)
        let analysis = try await api.analyze(request)
        #expect(analysis.parsedProducts.count == 5)

        let sessions = try await api.sessions()
        let hasCurrentSession = sessions.contains { $0.current }
        #expect(hasCurrentSession)
        let events = try await api.events()
        let hasLoginEvent = events.contains { $0.eventType.hasPrefix("login") || $0.eventType == "register" }
        #expect(hasLoginEvent)
        let identities = try await api.identities()
        #expect(identities.isEmpty)

        let signedOut = try await api.logout()
        #expect(signedOut.message.contains("signed out"))
        let afterLogout = try await api.session()
        #expect(afterLogout == nil)

        do {
            _ = try await api.me()
            Issue.record("expected 401 after logout")
        } catch let error as APIError {
            #expect(error.isUnauthorized)
        }
    }
}
