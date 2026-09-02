import Foundation

// MARK: - Request

/// Body of `POST /api/analyze`. Field names match the backend's Pydantic models
/// once the encoder converts to snake_case.
struct AnalyzeRequest: Codable, Equatable, Sendable {
    struct SkinProfilePayload: Codable, Equatable, Sendable {
        var skinType: String
        var concerns: [String]
    }

    struct ProductPayload: Codable, Equatable, Sendable {
        var brand: String
        var name: String
        var rawIngredientList: String
    }

    var skinProfile: SkinProfilePayload
    var amProducts: [ProductPayload]
    var pmProducts: [ProductPayload]
}

// MARK: - Response

enum Severity: String, Codable, Equatable, Sendable, Comparable {
    case low, medium, high

    var rank: Int {
        switch self {
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
}

/// Interaction type with a fallback so a new backend value cannot break decoding.
enum InteractionType: Equatable, Sendable, Codable {
    case conflict, caution, redundant, synergy
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InteractionType(rawValue: raw)
    }

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "conflict": self = .conflict
        case "caution": self = .caution
        case "redundant": self = .redundant
        case "synergy": self = .synergy
        default: self = .unknown(rawValue)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var rawValue: String {
        switch self {
        case .conflict: "conflict"
        case .caution: "caution"
        case .redundant: "redundant"
        case .synergy: "synergy"
        case .unknown(let value): value
        }
    }
}

enum InteractionScope: String, Codable, Equatable, Sendable {
    case direct, cumulative
}

enum ScoreStatus: String, Codable, Equatable, Sendable {
    case conflict, caution, clean
}

struct OverallScore: Codable, Equatable, Sendable {
    var status: ScoreStatus
    /// Present when status is `conflict`.
    var high: Int?
    var medium: Int?
    /// Present when status is `caution`.
    var count: Int?
}

/// The engine's view of an ingredient (`parser.Ingredient`).
struct EngineIngredient: Codable, Equatable, Sendable, Identifiable {
    var id: Int
    var inciName: String
    var synonyms: [String]
    var category: String?
    var phMin: Double?
    var phMax: Double?
    var comodogenic: Int?
    var altNames: [String]
}

/// A product as echoed back by the engine.
struct ProductReference: Codable, Equatable, Sendable {
    var name: String
    var brand: String
    var rawIngredientList: String
    var label: String
}

/// One conflict, caution, redundancy or synergy between two ingredients.
struct InteractionFinding: Codable, Equatable, Sendable, Identifiable {
    var interactionId: Int
    var interactionType: InteractionType
    var severity: Severity
    var baseSeverity: Severity
    var skinModifierApplied: Bool
    var scope: InteractionScope
    var mechanism: String?
    var description: String?
    var sourceCitation: String?
    var confidence: String?
    var ingredientA: EngineIngredient
    var ingredientB: EngineIngredient
    var productA: ProductReference
    var productB: ProductReference

    /// The same rule can fire for several product pairs, so the identity
    /// includes the products and scope.
    var id: String {
        "\(interactionId)|\(scope.rawValue)|\(productA.label)|\(productB.label)|\(ingredientA.id)|\(ingredientB.id)"
    }

    /// True when the skin profile raised the severity above the rule's base.
    var wasEscalated: Bool {
        skinModifierApplied && baseSeverity != severity
    }

    /// PubMed URL derived from a `PMID:12345` citation, when present.
    var evidenceURL: URL? {
        Citation.url(for: sourceCitation)
    }
}

struct UnresolvedToken: Codable, Equatable, Sendable, Identifiable {
    var product: String
    var rawToken: String
    var normalizedToken: String

    var id: String { "\(product)|\(normalizedToken)" }
}

struct ParsedProduct: Codable, Equatable, Sendable, Identifiable {
    struct UnknownToken: Codable, Equatable, Sendable, Identifiable {
        var rawToken: String
        var normalizedToken: String
        var id: String { normalizedToken }
    }

    var product: ProductReference
    var knownIngredients: [EngineIngredient]
    var unknownTokens: [UnknownToken]

    var id: String { product.label }
}

/// Full response of `POST /api/analyze`.
struct AnalysisResult: Codable, Equatable, Sendable {
    var overallScore: OverallScore
    var conflicts: [InteractionFinding]
    var cautions: [InteractionFinding]
    var synergies: [InteractionFinding]
    var unknownPairCount: Int
    var unresolvedTokens: [UnresolvedToken]
    var parsedProducts: [ParsedProduct]
}

enum Citation {
    /// `PMID:33377285` (any spacing or case) becomes a PubMed link. Anything
    /// else is shown as text only, never as a link to an unverified host.
    static func url(for citation: String?) -> URL? {
        guard let citation else { return nil }
        let pattern = #"PMID[:\s]*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: citation, range: NSRange(citation.startIndex..., in: citation)),
              let range = Range(match.range(at: 1), in: citation)
        else { return nil }
        return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(citation[range])/")
    }
}
