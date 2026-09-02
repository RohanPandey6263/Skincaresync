import Foundation

/// Every backend call the app makes. There is one production implementation
/// (`LiveAPIClient`) and one fixture-backed implementation (`MockAPIClient`)
/// used by previews and tests.
protocol APIClient: Sendable {
    func health() async throws -> HealthStatus

    func searchProducts(brand: String, name: String) async throws -> [ProductMatch]
    func lookupProduct(code: String) async throws -> ProductMatch
    func analyze(_ request: AnalyzeRequest) async throws -> AnalysisResult

    func searchIngredients(_ query: IngredientQuery) async throws -> IngredientSearchPage
    func suggestIngredients(_ text: String) async throws -> [IngredientSuggestion]
    func ingredientFacets() async throws -> CatalogFacets
    func ingredient(id: Int) async throws -> IngredientDetail

    /// `GET /api/auth/session`: nil when nobody is signed in.
    func session() async throws -> AuthSession?
    func register(email: String, password: String, displayName: String?) async throws -> MessageResponse
    func login(email: String, password: String) async throws -> AuthSession
    func logout() async throws -> MessageResponse
    func logoutAll() async throws -> MessageResponse
    func me() async throws -> AuthUser
    func verifyEmail(token: String) async throws -> MessageResponse
    func resendVerification(email: String) async throws -> MessageResponse
    func forgotPassword(email: String) async throws -> MessageResponse
    func resetPassword(token: String, password: String) async throws -> MessageResponse
    func changePassword(current: String, new: String) async throws -> MessageResponse
    func sessions() async throws -> [SessionInfo]
    func revokeSession(id: Int) async throws -> MessageResponse
    func events() async throws -> [AuthEvent]
    func identities() async throws -> [LinkedIdentity]
    func unlinkIdentity(provider: String) async throws -> MessageResponse
    func oauthProviders() async throws -> [OAuthProvider]
    func deactivate() async throws -> MessageResponse
    func deleteAccount(currentPassword: String) async throws -> MessageResponse

    /// Forgets any locally held credentials (cookies and CSRF token).
    func clearLocalSession()
}
