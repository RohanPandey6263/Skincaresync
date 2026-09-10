import Foundation

/// One product as returned by `/api/products/search` and `/api/products/code`.
/// Mirrors `lookup.ProductLookupResult` plus the match scores search adds.
struct ProductMatch: Codable, Equatable, Sendable, Identifiable {
    var code: String?
    var brand: String
    var name: String
    var rawIngredientList: String
    var source: String?
    var imageUrl: String?
    var productUrl: String?
    var similarityScore: Int?
    var ndc: String?
    var setid: String?
    var searchAliases: [String]?
    var brandSimilarityScore: Int?
    var nameSimilarityScore: Int?

    var id: String {
        setid ?? code ?? "\(brand):\(name)"
    }

    var label: String {
        [brand, name].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var sourceLabel: String {
        switch source {
        case "open_beauty_facts": "Open Beauty Facts"
        case "dailymed": "FDA DailyMed"
        case "brand_published", "brand": "Brand-published list"
        case "local_catalog", "catalog": "SkincareSync catalog"
        case let other?: other.replacingOccurrences(of: "_", with: " ").capitalized
        case nil: "Catalog"
        }
    }
}
