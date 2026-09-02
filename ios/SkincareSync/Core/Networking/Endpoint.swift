import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

enum APITimeouts {
    /// Catalog, health and auth calls.
    static let standard: TimeInterval = 12
    /// Product lookup fans out to DailyMed and Open Beauty Facts.
    static let lookup: TimeInterval = 20
}

/// A single API call, independent of the base URL it is sent to.
struct Endpoint: Equatable, Sendable {
    var path: String
    var method: HTTPMethod = .get
    var query: [URLQueryItem] = []
    var body: Data? = nil
    var timeout: TimeInterval = APITimeouts.standard

    /// Resolves against `base`, preserving any path prefix the base carries.
    func url(relativeTo base: URL) throws -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents()
        components.scheme = base.scheme
        components.host = base.host
        components.port = base.port
        let basePath = base.path.hasSuffix("/") ? String(base.path.dropLast()) : base.path
        components.path = basePath + "/" + trimmed
        if !query.isEmpty {
            components.percentEncodedQuery = Self.encodeQuery(query)
        }
        guard let url = components.url else {
            throw APIError.notConfigured("Could not build a URL for \(path).")
        }
        return url
    }

    func urlRequest(base: URL, csrfToken: String?) throws -> URLRequest {
        var request = URLRequest(url: try url(relativeTo: base))
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if method != .get, let csrfToken, !csrfToken.isEmpty {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        }
        return request
    }

    /// Percent-encodes every query value strictly. `URLComponents` leaves `+`
    /// alone, which the server would read as a space.
    static func encodeQuery(_ items: [URLQueryItem]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?/;:#@[]")
        return items.map { item in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? item.name
            guard let value = item.value else { return name }
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(name)=\(encoded)"
        }.joined(separator: "&")
    }
}

/// Every endpoint the app uses, as data. Bodies are encoded with the shared
/// snake_case encoder so the Swift models stay camelCase.
enum API {
    static var health: Endpoint { Endpoint(path: "/api/health") }

    static func searchProducts(brand: String, name: String) -> Endpoint {
        Endpoint(
            path: "/api/products/search",
            query: [URLQueryItem(name: "brand", value: brand), URLQueryItem(name: "name", value: name)],
            timeout: APITimeouts.lookup
        )
    }

    static func productByCode(_ code: String) -> Endpoint {
        Endpoint(
            path: "/api/products/code",
            query: [URLQueryItem(name: "value", value: code)],
            timeout: APITimeouts.lookup
        )
    }

    static func analyze(_ request: AnalyzeRequest) throws -> Endpoint {
        Endpoint(path: "/api/analyze", method: .post, body: try APICoding.encoder.encode(request))
    }

    static func ingredients(_ query: IngredientQuery) -> Endpoint {
        Endpoint(path: "/api/ingredients", query: query.queryItems)
    }

    static func suggestIngredients(_ text: String, limit: Int = 8) -> Endpoint {
        Endpoint(
            path: "/api/ingredients/suggest",
            query: [URLQueryItem(name: "q", value: text), URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    static var ingredientFacets: Endpoint { Endpoint(path: "/api/ingredients/facets") }

    static func ingredient(id: Int) -> Endpoint { Endpoint(path: "/api/ingredients/\(id)") }

    // MARK: Auth

    static var session: Endpoint { Endpoint(path: "/api/auth/session") }
    static var me: Endpoint { Endpoint(path: "/api/auth/me") }

    static func register(email: String, password: String, displayName: String?) throws -> Endpoint {
        struct Body: Encodable { var email: String; var password: String; var displayName: String? }
        return Endpoint(path: "/api/auth/register", method: .post,
                        body: try APICoding.encoder.encode(Body(email: email, password: password, displayName: displayName)))
    }

    static func login(email: String, password: String) throws -> Endpoint {
        struct Body: Encodable { var email: String; var password: String }
        return Endpoint(path: "/api/auth/login", method: .post,
                        body: try APICoding.encoder.encode(Body(email: email, password: password)))
    }

    static var logout: Endpoint { Endpoint(path: "/api/auth/logout", method: .post) }
    static var logoutAll: Endpoint { Endpoint(path: "/api/auth/logout-all", method: .post) }

    static func verifyEmail(token: String) throws -> Endpoint {
        struct Body: Encodable { var token: String }
        return Endpoint(path: "/api/auth/verify-email", method: .post, body: try APICoding.encoder.encode(Body(token: token)))
    }

    static func resendVerification(email: String) throws -> Endpoint {
        struct Body: Encodable { var email: String }
        return Endpoint(path: "/api/auth/resend-verification", method: .post, body: try APICoding.encoder.encode(Body(email: email)))
    }

    static func forgotPassword(email: String) throws -> Endpoint {
        struct Body: Encodable { var email: String }
        return Endpoint(path: "/api/auth/forgot-password", method: .post, body: try APICoding.encoder.encode(Body(email: email)))
    }

    static func resetPassword(token: String, password: String) throws -> Endpoint {
        struct Body: Encodable { var token: String; var password: String }
        return Endpoint(path: "/api/auth/reset-password", method: .post,
                        body: try APICoding.encoder.encode(Body(token: token, password: password)))
    }

    static func changePassword(current: String, new: String) throws -> Endpoint {
        struct Body: Encodable { var currentPassword: String; var password: String }
        return Endpoint(path: "/api/auth/change-password", method: .post,
                        body: try APICoding.encoder.encode(Body(currentPassword: current, password: new)))
    }

    static var sessions: Endpoint { Endpoint(path: "/api/auth/sessions") }
    static func revokeSession(id: Int) -> Endpoint { Endpoint(path: "/api/auth/sessions/\(id)", method: .delete) }
    static var events: Endpoint { Endpoint(path: "/api/auth/events") }
    static var identities: Endpoint { Endpoint(path: "/api/auth/identities") }
    static func unlinkIdentity(provider: String) -> Endpoint {
        let safe = provider.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? provider
        return Endpoint(path: "/api/auth/identities/\(safe)", method: .delete)
    }
    static var oauthProviders: Endpoint { Endpoint(path: "/api/auth/oauth/providers") }
    static var deactivate: Endpoint { Endpoint(path: "/api/auth/deactivate", method: .post) }

    static func deleteAccount(currentPassword: String) throws -> Endpoint {
        struct Body: Encodable { var currentPassword: String; var confirm: String }
        return Endpoint(path: "/api/auth/delete", method: .post,
                        body: try APICoding.encoder.encode(Body(currentPassword: currentPassword, confirm: "DELETE")))
    }
}

/// Parameters for `GET /api/ingredients`.
struct IngredientQuery: Equatable, Sendable {
    var text: String = ""
    var functions: [String] = []
    var source: String? = nil
    var letter: String? = nil
    var onlyWithInteractions = false
    var onlyRestricted = false
    var limit = 20
    var offset = 0

    var hasFilters: Bool {
        !functions.isEmpty || source != nil || letter != nil || onlyWithInteractions || onlyRestricted
    }

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        for function in functions {
            items.append(URLQueryItem(name: "functions", value: function))
        }
        if let source { items.append(URLQueryItem(name: "source", value: source)) }
        if let letter { items.append(URLQueryItem(name: "letter", value: letter)) }
        if onlyWithInteractions { items.append(URLQueryItem(name: "only_with_interactions", value: "true")) }
        if onlyRestricted { items.append(URLQueryItem(name: "only_restricted", value: "true")) }
        return items
    }
}
