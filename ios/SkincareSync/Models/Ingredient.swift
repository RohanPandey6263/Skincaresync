import Foundation

/// A catalog row from `GET /api/ingredients`.
struct IngredientSummary: Codable, Equatable, Sendable, Identifiable {
    var id: Int
    var inciName: String
    var displayName: String
    var altNames: [String]
    var synonyms: [String]
    var category: String?
    var functions: [String]
    var description: String?
    var casNumber: String?
    var einecsNumber: String?
    var innName: String?
    var phEurName: String?
    var cosingRef: String?
    var wikidataId: String?
    var restriction: String?
    var obfId: String?
    var phMin: Double?
    var phMax: Double?
    var comodogenic: Int?
    var source: String
    var sourceUpdatedOn: String?
    var interactionCount: Int

    var isCurated: Bool { source == "curated" }
    var isInEngine: Bool { interactionCount > 0 }
    var isRestricted: Bool { !(restriction ?? "").isEmpty }
}

struct IngredientSearchPage: Codable, Equatable, Sendable {
    var items: [IngredientSummary]
    var total: Int
    var limit: Int
    var offset: Int
    var hasMore: Bool
    var query: String
}

struct IngredientSuggestion: Codable, Equatable, Sendable, Identifiable {
    var id: Int
    var inciName: String
    var displayName: String
    var category: String?
    var functions: [String]
    var source: String
    var interactionCount: Int
}

struct CatalogFacets: Codable, Equatable, Sendable {
    struct FunctionCount: Codable, Equatable, Sendable, Identifiable {
        var value: String
        var count: Int
        var id: String { value }
    }

    struct LetterCount: Codable, Equatable, Sendable, Identifiable {
        var letter: String
        var count: Int
        var id: String { letter }
    }

    struct Stats: Codable, Equatable, Sendable {
        var total: Int
        var curated: Int
        var withDescription: Int
        var withAltNames: Int
        var withInteractions: Int
        var withRestriction: Int
    }

    var functions: [FunctionCount]
    var letters: [LetterCount]
    var stats: Stats
}

/// A rule involving this ingredient, from `GET /api/ingredients/{id}`.
struct IngredientInteraction: Codable, Equatable, Sendable, Identifiable {
    var interactionId: Int
    var interactionType: InteractionType
    var severity: Severity
    var conflictScope: String
    var mechanism: String?
    var description: String?
    var sourceCitation: String?
    var partnerId: Int
    var partnerName: String
    var partnerDisplayName: String

    var id: Int { interactionId }
    var evidenceURL: URL? { Citation.url(for: sourceCitation) }
}

struct RelatedIngredient: Codable, Equatable, Sendable, Identifiable {
    var id: Int
    var inciName: String
    var category: String?
    var displayName: String
}

/// Full detail: the summary fields plus interactions and related entries.
struct IngredientDetail: Codable, Equatable, Sendable, Identifiable {
    var id: Int
    var inciName: String
    var displayName: String
    var altNames: [String]
    var synonyms: [String]
    var category: String?
    var functions: [String]
    var description: String?
    var casNumber: String?
    var einecsNumber: String?
    var innName: String?
    var phEurName: String?
    var cosingRef: String?
    var wikidataId: String?
    var restriction: String?
    var obfId: String?
    var phMin: Double?
    var phMax: Double?
    var comodogenic: Int?
    var source: String
    var sourceUpdatedOn: String?
    var interactionCount: Int
    var interactions: [IngredientInteraction]
    var related: [RelatedIngredient]

    var isCurated: Bool { source == "curated" }
    var isInEngine: Bool { interactionCount > 0 }
    var isRestricted: Bool { !(restriction ?? "").isEmpty }

    /// Names shown under "Also known as", deduplicated and capped.
    var aliases: [String] {
        var seen = Set<String>()
        return (synonyms + altNames).filter { seen.insert($0.lowercased()).inserted }.prefix(24).map { $0 }
    }

    /// First identifier of a slash-separated list such as "68-26-8 / 11103-57-4".
    var primaryCAS: String? {
        guard let casNumber else { return nil }
        let first = casNumber.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return (first?.isEmpty == false) ? first : nil
    }

    var pubChemURL: URL? {
        guard let cas = primaryCAS,
              let encoded = cas.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://pubchem.ncbi.nlm.nih.gov/#query=\(encoded)")
    }

    var wikidataURL: URL? {
        guard let wikidataId, !wikidataId.isEmpty,
              let encoded = wikidataId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://www.wikidata.org/wiki/\(encoded)")
    }

    var openBeautyFactsURL: URL? {
        guard let obfId, !obfId.isEmpty else { return nil }
        let slug = obfId.hasPrefix("en:") ? String(obfId.dropFirst(3)) : obfId
        guard let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://world.openbeautyfacts.org/ingredient/\(encoded)")
    }
}

enum IngredientFormatting {
    /// "skin-conditioning" -> "Skin conditioning".
    static func functionLabel(_ slug: String) -> String {
        let spaced = slug.replacingOccurrences(of: "-", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
