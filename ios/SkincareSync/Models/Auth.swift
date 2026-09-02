import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    var userId: Int
    var email: String
    var displayName: String?
    var role: String
    var status: String
    var emailVerified: Bool
    var hasPassword: Bool
    var createdAt: Date

    var isAdmin: Bool { role == "admin" }
}

/// `LoginResponse`: returned by `/api/auth/login` and `/api/auth/session`.
struct AuthSession: Codable, Equatable, Sendable {
    var user: AuthUser
    var csrfToken: String
    var redirectTo: String
}

struct MessageResponse: Codable, Equatable, Sendable {
    var message: String
    /// Only populated when the backend runs with AUTH_DEV_ECHO_TOKENS.
    var devToken: String?
}

struct SessionInfo: Codable, Equatable, Sendable, Identifiable {
    var sessionId: Int
    var createdAt: Date
    var lastSeenAt: Date
    var ipAddress: String?
    var userAgent: String?
    var current: Bool

    var id: Int { sessionId }
}

struct AuthEvent: Codable, Equatable, Sendable, Identifiable {
    var eventType: String
    var createdAt: Date
    var ipAddress: String?
    var detail: [String: JSONValue]

    var id: String { "\(eventType)|\(createdAt.timeIntervalSince1970)|\(ipAddress ?? "")" }

    /// "password.changed" -> "Password changed".
    var title: String {
        let words = eventType.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

struct LinkedIdentity: Codable, Equatable, Sendable, Identifiable {
    var provider: String
    var email: String?
    var createdAt: Date
    var lastLoginAt: Date?

    var id: String { provider }

    var providerLabel: String {
        switch provider {
        case "google": "Google"
        case "apple": "Apple"
        default: provider.capitalized
        }
    }
}

struct OAuthProvider: Codable, Equatable, Sendable, Identifiable {
    var key: String
    var displayName: String
    var id: String { key }
}

/// Arbitrary JSON, used for the free-form `detail` on audit events.
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Short human rendering for audit detail rows.
    var displayText: String {
        switch self {
        case .string(let value): value
        case .number(let value): value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value): value ? "yes" : "no"
        case .null: "—"
        case .array(let values): values.map(\.displayText).joined(separator: ", ")
        case .object(let values): values.keys.sorted().map { "\($0): \(values[$0]!.displayText)" }.joined(separator: ", ")
        }
    }
}
