import Foundation

/// Where the app sends requests. Read from `APIBaseURL` in Info.plist, which
/// the xcconfig files fill per build configuration.
struct APIConfiguration: Equatable, Sendable {
    let baseURL: URL

    var hostDescription: String {
        var text = baseURL.host ?? baseURL.absoluteString
        if let port = baseURL.port { text += ":\(port)" }
        return text
    }

    enum Failure: Error, Equatable, Sendable {
        case missing
        case invalid(String)
        case insecure(String)

        var message: String {
            switch self {
            case .missing:
                "No API base URL is set for this build. Set API_BASE_URL in the xcconfig for this configuration."
            case .invalid(let value):
                "The configured API base URL is not a valid URL: \(value)"
            case .insecure(let value):
                "Release builds must talk to an HTTPS endpoint. The configured value is \(value)."
            }
        }
    }

    /// Parses a raw value. `requireHTTPS` is true in release builds.
    static func parse(_ raw: String?, requireHTTPS: Bool) -> Result<APIConfiguration, Failure> {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.missing) }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), url.host != nil else {
            return .failure(.invalid(trimmed))
        }
        guard scheme == "https" || (!requireHTTPS && scheme == "http") else {
            return .failure(.insecure(trimmed))
        }
        return .success(APIConfiguration(baseURL: url))
    }

    static func fromBundle(_ bundle: Bundle = .main) -> Result<APIConfiguration, Failure> {
        let raw = bundle.object(forInfoDictionaryKey: "APIBaseURL") as? String
        #if DEBUG
        return parse(raw, requireHTTPS: false)
        #else
        return parse(raw, requireHTTPS: true)
        #endif
    }
}
