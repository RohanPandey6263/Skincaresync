import Foundation
import os

/// Fixture-backed client for previews and tests. Every response can be
/// replaced per call so a test can drive error, empty and slow paths.
///
/// Test-only convenience: state is guarded by a lock, so it is safe to configure
/// from a test and read from the app under test.
final class MockAPIClient: APIClient, @unchecked Sendable {
    typealias Handler<Input, Output> = @Sendable (Input) async throws -> Output

    struct Recorded: Sendable {
        var analyzeRequests: [AnalyzeRequest] = []
        var productSearches: [(brand: String, name: String)] = []
        var codeLookups: [String] = []
        var ingredientQueries: [IngredientQuery] = []
        var suggestions: [String] = []
        var logoutCalls = 0
        var clearLocalSessionCalls = 0
    }

    private let lock = OSAllocatedUnfairLock<Recorded>(initialState: Recorded())

    /// Artificial latency so previews show loading states.
    var latency: Duration = .zero

    var healthHandler: Handler<Void, HealthStatus> = { _ in Fixtures.health }
    var searchProductsHandler: Handler<(brand: String, name: String), [ProductMatch]> = { _ in Fixtures.productSearch }
    var lookupProductHandler: Handler<String, ProductMatch> = { _ in Fixtures.productSearch[0] }
    var analyzeHandler: Handler<AnalyzeRequest, AnalysisResult> = { _ in Fixtures.analysis }
    var searchIngredientsHandler: Handler<IngredientQuery, IngredientSearchPage> = { _ in Fixtures.ingredientSearch }
    var suggestHandler: Handler<String, [IngredientSuggestion]> = { _ in Fixtures.ingredientSuggestions }
    var facetsHandler: Handler<Void, CatalogFacets> = { _ in Fixtures.ingredientFacets }
    var ingredientHandler: Handler<Int, IngredientDetail> = { _ in Fixtures.ingredientDetail }

    var sessionHandler: Handler<Void, AuthSession?> = { _ in nil }
    var loginHandler: Handler<(email: String, password: String), AuthSession> = { _ in Fixtures.authSession }
    var registerHandler: Handler<(email: String, password: String, displayName: String?), MessageResponse> = { _ in
        MessageResponse(message: "If that email address needs confirming, we have sent a message to it. Check your inbox, including spam.", devToken: nil)
    }
    var messageHandler: Handler<String, MessageResponse> = { name in MessageResponse(message: "\(name) succeeded.", devToken: nil) }
    var meHandler: Handler<Void, AuthUser> = { _ in Fixtures.authSession.user }
    var sessionsHandler: Handler<Void, [SessionInfo]> = { _ in Fixtures.authSessions }
    var eventsHandler: Handler<Void, [AuthEvent]> = { _ in Fixtures.authEvents }
    var identitiesHandler: Handler<Void, [LinkedIdentity]> = { _ in Fixtures.authIdentities }
    var providersHandler: Handler<Void, [OAuthProvider]> = { _ in Fixtures.oauthProviders }

    init() {}

    var recorded: Recorded { lock.withLock { $0 } }

    private func record(_ update: @Sendable (inout Recorded) -> Void) {
        lock.withLock { update(&$0) }
    }

    private func wait() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
        try Task.checkCancellation()
    }

    func health() async throws -> HealthStatus { try await wait(); return try await healthHandler(()) }

    func searchProducts(brand: String, name: String) async throws -> [ProductMatch] {
        record { $0.productSearches.append((brand, name)) }
        try await wait()
        return try await searchProductsHandler((brand, name))
    }

    func lookupProduct(code: String) async throws -> ProductMatch {
        record { $0.codeLookups.append(code) }
        try await wait()
        return try await lookupProductHandler(code)
    }

    func analyze(_ request: AnalyzeRequest) async throws -> AnalysisResult {
        record { $0.analyzeRequests.append(request) }
        try await wait()
        return try await analyzeHandler(request)
    }

    func searchIngredients(_ query: IngredientQuery) async throws -> IngredientSearchPage {
        record { $0.ingredientQueries.append(query) }
        try await wait()
        return try await searchIngredientsHandler(query)
    }

    func suggestIngredients(_ text: String) async throws -> [IngredientSuggestion] {
        record { $0.suggestions.append(text) }
        try await wait()
        return try await suggestHandler(text)
    }

    func ingredientFacets() async throws -> CatalogFacets { try await wait(); return try await facetsHandler(()) }
    func ingredient(id: Int) async throws -> IngredientDetail { try await wait(); return try await ingredientHandler(id) }

    func session() async throws -> AuthSession? { try await wait(); return try await sessionHandler(()) }

    func register(email: String, password: String, displayName: String?) async throws -> MessageResponse {
        try await wait(); return try await registerHandler((email, password, displayName))
    }

    func login(email: String, password: String) async throws -> AuthSession {
        try await wait(); return try await loginHandler((email, password))
    }

    func logout() async throws -> MessageResponse {
        record { $0.logoutCalls += 1 }
        try await wait()
        return try await messageHandler("logout")
    }

    func logoutAll() async throws -> MessageResponse { try await wait(); return try await messageHandler("logout-all") }
    func me() async throws -> AuthUser { try await wait(); return try await meHandler(()) }
    func verifyEmail(token: String) async throws -> MessageResponse { try await wait(); return try await messageHandler("verify-email") }
    func resendVerification(email: String) async throws -> MessageResponse { try await wait(); return try await messageHandler("resend-verification") }
    func forgotPassword(email: String) async throws -> MessageResponse { try await wait(); return try await messageHandler("forgot-password") }
    func resetPassword(token: String, password: String) async throws -> MessageResponse { try await wait(); return try await messageHandler("reset-password") }
    func changePassword(current: String, new: String) async throws -> MessageResponse { try await wait(); return try await messageHandler("change-password") }
    func sessions() async throws -> [SessionInfo] { try await wait(); return try await sessionsHandler(()) }
    func revokeSession(id: Int) async throws -> MessageResponse { try await wait(); return try await messageHandler("revoke-session") }
    func events() async throws -> [AuthEvent] { try await wait(); return try await eventsHandler(()) }
    func identities() async throws -> [LinkedIdentity] { try await wait(); return try await identitiesHandler(()) }
    func unlinkIdentity(provider: String) async throws -> MessageResponse { try await wait(); return try await messageHandler("unlink") }
    func oauthProviders() async throws -> [OAuthProvider] { try await wait(); return try await providersHandler(()) }
    func deactivate() async throws -> MessageResponse { try await wait(); return try await messageHandler("deactivate") }
    func deleteAccount(currentPassword: String) async throws -> MessageResponse { try await wait(); return try await messageHandler("delete") }

    func clearLocalSession() { record { $0.clearLocalSessionCalls += 1 } }
}

extension MockAPIClient {
    /// A mock that behaves like a signed-in backend, for previews.
    static func signedIn() -> MockAPIClient {
        let client = MockAPIClient()
        client.sessionHandler = { _ in Fixtures.authSession }
        return client
    }

    /// A mock whose every call fails the same way, for error-state previews.
    static func failing(_ error: APIError) -> MockAPIClient {
        let client = MockAPIClient()
        client.healthHandler = { _ in throw error }
        client.searchProductsHandler = { _ in throw error }
        client.lookupProductHandler = { _ in throw error }
        client.analyzeHandler = { _ in throw error }
        client.searchIngredientsHandler = { _ in throw error }
        client.suggestHandler = { _ in throw error }
        client.facetsHandler = { _ in throw error }
        client.ingredientHandler = { _ in throw error }
        client.sessionHandler = { _ in throw error }
        client.loginHandler = { _ in throw error }
        return client
    }
}
