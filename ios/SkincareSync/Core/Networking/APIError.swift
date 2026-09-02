import Foundation

/// Every failure the app surfaces. Transport errors are collapsed into a few
/// cases with user-facing copy; server errors keep the status and the
/// backend's `detail` message.
enum APIError: Error, Equatable, Sendable {
    /// The build has no usable API base URL.
    case notConfigured(String)
    /// The device has no network route at all.
    case offline
    /// The device is online but the backend did not answer.
    case unreachable(host: String)
    case timeout
    /// The caller cancelled the request. Never shown as an error.
    case cancelled
    /// A non-2xx response with a plain `detail` string (or a status fallback).
    case server(status: Int, message: String, retryAfterSeconds: Int?)
    /// A 422 whose `detail` was a list of field errors.
    case validation(fieldErrors: [String: String])
    case decoding(String)
    case invalidResponse

    var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }

    var isRateLimited: Bool {
        if case .server(429, _, _) = self { return true }
        return false
    }

    var isUnauthorized: Bool {
        if case .server(401, _, _) = self { return true }
        return false
    }

    var isNotFound: Bool {
        if case .server(404, _, _) = self { return true }
        return false
    }

    var isConnectivity: Bool {
        switch self {
        case .offline, .unreachable, .timeout: true
        default: false
        }
    }

    var status: Int? {
        if case .server(let status, _, _) = self { return status }
        if case .validation = self { return 422 }
        return nil
    }

    var fieldErrors: [String: String] {
        if case .validation(let errors) = self { return errors }
        return [:]
    }

    /// Short heading for a full-screen error state.
    var title: String {
        switch self {
        case .notConfigured: "Backend not configured"
        case .offline: "You're offline"
        case .unreachable: "Can't reach SkincareSync"
        case .timeout: "That took too long"
        case .cancelled: "Cancelled"
        case .server(let status, _, _):
            switch status {
            case 401: "Sign in to continue"
            case 403: "Session not verified"
            case 404: "Nothing found"
            case 429: "Slow down a moment"
            case 502, 503, 504: "Service unavailable"
            default: "Something went wrong"
            }
        case .validation: "Check the highlighted fields"
        case .decoding: "Unexpected response"
        case .invalidResponse: "Unexpected response"
        }
    }

    /// User-facing sentence. Never includes a stack trace, token or cookie.
    var message: String {
        switch self {
        case .notConfigured(let reason):
            reason
        case .offline:
            "Connect to the internet and try again."
        case .unreachable(let host):
            "Confirm the backend is running at \(host) and reachable from this device."
        case .timeout:
            "The request timed out. Please try again."
        case .cancelled:
            "The request was cancelled."
        case .server(let status, let message, let retryAfter):
            if status == 429, let retryAfter {
                "\(message) You can retry in about \(retryAfter) second\(retryAfter == 1 ? "" : "s")."
            } else {
                message
            }
        case .validation(let errors):
            errors.values.sorted().joined(separator: " ")
        case .decoding:
            "The server sent a response this version of the app could not read."
        case .invalidResponse:
            "The server sent an unexpected response."
        }
    }

    var symbol: String {
        switch self {
        case .offline: "wifi.slash"
        case .unreachable, .notConfigured: "server.rack"
        case .timeout: "clock.badge.exclamationmark"
        case .server(429, _, _): "hourglass"
        case .server(404, _, _): "magnifyingglass"
        default: "exclamationmark.circle"
        }
    }

    /// Fallback copy for statuses whose body carried no message.
    static func fallbackMessage(for status: Int) -> String {
        switch status {
        case 401: "Sign in to continue."
        case 403: "Your session could not be verified. Sign in again and retry."
        case 404: "We could not find a match for that request."
        case 408: "That request took too long. Please try again."
        case 422: "Some of the submitted values were not valid."
        case 429: "Too many requests. Please wait a moment and try again."
        case 502: "The product lookup service is unavailable right now."
        case 503: "The service is busy. Please try again in a moment."
        case 504: "The service took too long to respond. Please try again."
        default: "Request failed (\(status))."
        }
    }

    /// Maps a transport-level error to one of the connectivity cases.
    static func from(urlError: URLError, host: String) -> APIError {
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .internationalRoamingOff, .dataNotAllowed:
            return .offline
        default:
            return .unreachable(host: host)
        }
    }
}

/// Shape of a FastAPI error body: `{"detail": "..."}` or a list of field errors.
struct ServerErrorBody: Decodable {
    enum Detail: Decodable {
        case message(String)
        case fields([FieldError])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .message(text)
            } else if let list = try? container.decode([FieldError].self) {
                self = .fields(list)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown detail shape")
            }
        }
    }

    struct FieldError: Decodable {
        enum Location: Decodable {
            case name(String)
            case index(Int)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) {
                    self = .name(text)
                } else {
                    self = .index(try container.decode(Int.self))
                }
            }
        }

        var loc: [Location]
        var msg: String

        /// Last named path component, e.g. `password`.
        var field: String? {
            for element in loc.reversed() {
                if case .name(let name) = element, name != "body" { return name }
            }
            return nil
        }

        /// Pydantic prefixes custom validator messages with "Value error, ".
        var cleanMessage: String {
            msg.replacingOccurrences(of: #"^Value error,\s*"#, with: "", options: .regularExpression)
        }
    }

    var detail: Detail

    func apiError(status: Int, retryAfter: Int?) -> APIError {
        switch detail {
        case .message(let text):
            return .server(status: status, message: text, retryAfterSeconds: retryAfter)
        case .fields(let errors):
            var map: [String: String] = [:]
            for error in errors {
                map[error.field ?? "request"] = error.cleanMessage
            }
            return map.isEmpty
                ? .server(status: status, message: APIError.fallbackMessage(for: status), retryAfterSeconds: retryAfter)
                : .validation(fieldErrors: map)
        }
    }
}
