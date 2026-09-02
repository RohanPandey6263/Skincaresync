import Foundation
import os

/// URLSession-backed client. Cookies live in the session's shared cookie
/// storage, so the HttpOnly session cookie set by `/api/auth/login` is sent
/// back automatically. The CSRF token is read from the non-HttpOnly cookie the
/// backend sets, with the value returned in the login body as a fallback.
final class LiveAPIClient: APIClient, Sendable {
    static let csrfCookieName = "skincaresync_csrf"
    static let sessionCookieName = "skincaresync_session"

    let configuration: APIConfiguration
    private let session: URLSession
    private let csrfToken = OSAllocatedUnfairLock<String?>(initialState: nil)

    init(configuration: APIConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let sessionConfiguration = URLSessionConfiguration.default
            sessionConfiguration.httpCookieAcceptPolicy = .always
            sessionConfiguration.httpShouldSetCookies = true
            sessionConfiguration.waitsForConnectivity = false
            sessionConfiguration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    private static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "SkincareSync-iOS/\(version)"
    }

    // MARK: Catalog and analysis

    func health() async throws -> HealthStatus {
        // 503 carries a well-formed body with `ok: false`; surface it rather than failing.
        let (data, response) = try await perform(API.health)
        if response.statusCode == 503, let status = try? APICoding.decoder.decode(HealthStatus.self, from: data) {
            return status
        }
        return try decode(HealthStatus.self, from: data, response: response)
    }

    func searchProducts(brand: String, name: String) async throws -> [ProductMatch] {
        try await send(API.searchProducts(brand: brand, name: name))
    }

    func lookupProduct(code: String) async throws -> ProductMatch {
        try await send(API.productByCode(code))
    }

    func analyze(_ request: AnalyzeRequest) async throws -> AnalysisResult {
        try await send(try API.analyze(request))
    }

    func searchIngredients(_ query: IngredientQuery) async throws -> IngredientSearchPage {
        try await send(API.ingredients(query))
    }

    func suggestIngredients(_ text: String) async throws -> [IngredientSuggestion] {
        try await send(API.suggestIngredients(text))
    }

    func ingredientFacets() async throws -> CatalogFacets {
        try await send(API.ingredientFacets)
    }

    func ingredient(id: Int) async throws -> IngredientDetail {
        try await send(API.ingredient(id: id))
    }

    // MARK: Auth

    func session() async throws -> AuthSession? {
        let (data, response) = try await perform(API.session)
        guard (200..<300).contains(response.statusCode) else {
            throw serverError(data: data, response: response)
        }
        if Self.isJSONNull(data) {
            csrfToken.withLock { $0 = nil }
            return nil
        }
        let session = try decodeBody(AuthSession.self, from: data)
        csrfToken.withLock { $0 = session.csrfToken }
        return session
    }

    func register(email: String, password: String, displayName: String?) async throws -> MessageResponse {
        try await send(try API.register(email: email, password: password, displayName: displayName))
    }

    func login(email: String, password: String) async throws -> AuthSession {
        let session: AuthSession = try await send(try API.login(email: email, password: password))
        csrfToken.withLock { $0 = session.csrfToken }
        return session
    }

    func logout() async throws -> MessageResponse {
        defer { clearLocalSession() }
        return try await send(API.logout)
    }

    func logoutAll() async throws -> MessageResponse {
        defer { clearLocalSession() }
        return try await send(API.logoutAll)
    }

    func me() async throws -> AuthUser { try await send(API.me) }

    func verifyEmail(token: String) async throws -> MessageResponse {
        try await send(try API.verifyEmail(token: token))
    }

    func resendVerification(email: String) async throws -> MessageResponse {
        try await send(try API.resendVerification(email: email))
    }

    func forgotPassword(email: String) async throws -> MessageResponse {
        try await send(try API.forgotPassword(email: email))
    }

    func resetPassword(token: String, password: String) async throws -> MessageResponse {
        defer { clearLocalSession() }
        return try await send(try API.resetPassword(token: token, password: password))
    }

    func changePassword(current: String, new: String) async throws -> MessageResponse {
        try await send(try API.changePassword(current: current, new: new))
    }

    func sessions() async throws -> [SessionInfo] { try await send(API.sessions) }
    func revokeSession(id: Int) async throws -> MessageResponse { try await send(API.revokeSession(id: id)) }
    func events() async throws -> [AuthEvent] { try await send(API.events) }
    func identities() async throws -> [LinkedIdentity] { try await send(API.identities) }
    func unlinkIdentity(provider: String) async throws -> MessageResponse {
        try await send(API.unlinkIdentity(provider: provider))
    }
    func oauthProviders() async throws -> [OAuthProvider] { try await send(API.oauthProviders) }

    func deactivate() async throws -> MessageResponse {
        defer { clearLocalSession() }
        return try await send(API.deactivate)
    }

    func deleteAccount(currentPassword: String) async throws -> MessageResponse {
        defer { clearLocalSession() }
        return try await send(try API.deleteAccount(currentPassword: currentPassword))
    }

    func clearLocalSession() {
        csrfToken.withLock { $0 = nil }
        guard let storage = session.configuration.httpCookieStorage else { return }
        for cookie in storage.cookies(for: configuration.baseURL) ?? [] {
            storage.deleteCookie(cookie)
        }
    }

    // MARK: Transport

    /// The CSRF token to echo: the live cookie wins because the backend reissues
    /// it on some calls; the body value from login is the fallback.
    private func currentCSRFToken() -> String? {
        let cookies = session.configuration.httpCookieStorage?.cookies(for: configuration.baseURL) ?? []
        if let cookie = cookies.first(where: { $0.name == Self.csrfCookieName }), !cookie.value.isEmpty {
            return cookie.value
        }
        return csrfToken.withLock { $0 }
    }

    private func perform(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        let request = try endpoint.urlRequest(base: configuration.baseURL, csrfToken: currentCSRFToken())
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.from(urlError: error, host: configuration.hostDescription)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.unreachable(host: configuration.hostDescription)
        }
    }

    private func send<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let (data, response) = try await perform(endpoint)
        return try decode(T.self, from: data, response: response)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> T {
        guard (200..<300).contains(response.statusCode) else {
            throw serverError(data: data, response: response)
        }
        return try decodeBody(type, from: data)
    }

    private func decodeBody<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try APICoding.decoder.decode(type, from: data)
        } catch {
            throw APIError.decoding(String(describing: type))
        }
    }

    private func serverError(data: Data, response: HTTPURLResponse) -> APIError {
        Self.serverError(status: response.statusCode, body: data,
                         retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }

    /// Builds the error for a non-2xx response. Exposed for tests.
    static func serverError(status: Int, body: Data, retryAfter: String?) -> APIError {
        let retrySeconds = retryAfter.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if let parsed = try? APICoding.decoder.decode(ServerErrorBody.self, from: body) {
            return parsed.apiError(status: status, retryAfter: retrySeconds)
        }
        return .server(status: status, message: APIError.fallbackMessage(for: status), retryAfterSeconds: retrySeconds)
    }

    static func isJSONNull(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null"
    }
}
