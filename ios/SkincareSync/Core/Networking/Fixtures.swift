import Foundation

private final class FixtureBundleMarker {}

/// Deterministic sample payloads captured from the real backend. Used only by
/// previews, the mock client and tests; the live app never falls back to them.
enum Fixtures {
    static let health: HealthStatus = load("health")
    static let productSearch: [ProductMatch] = load("product_search")
    static let analysis: AnalysisResult = load("analysis")
    static let ingredientSearch: IngredientSearchPage = load("ingredient_search")
    static let ingredientSuggestions: [IngredientSuggestion] = load("ingredient_suggest")
    static let ingredientFacets: CatalogFacets = load("ingredient_facets")
    static let ingredientDetail: IngredientDetail = load("ingredient_detail")
    static let authSession: AuthSession = load("auth_session")
    static let authSessions: [SessionInfo] = load("auth_sessions")
    static let authEvents: [AuthEvent] = load("auth_events")
    static let authIdentities: [LinkedIdentity] = load("auth_identities")
    static let oauthProviders: [OAuthProvider] = load("oauth_providers")

    /// Stable identifiers so the same draft compares equal across accesses.
    static let sampleDraft: RoutineDraft = {
        func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
        return RoutineDraft(
            profile: SkinProfile(skinType: .sensitive, concerns: [.rosacea, .acne]),
            am: [
                RoutineProduct(id: id(1), brand: "Example", name: "Vitamin C Serum",
                               rawIngredientList: "Ingredients: Water, Ascorbic Acid, Glycerin, Tocopherol, Ferulic Acid"),
                RoutineProduct(id: id(2), brand: "Example", name: "Niacinamide Serum",
                               rawIngredientList: "Water, Niacinamide, Zinc PCA, Unobtainium Extract"),
                RoutineProduct(id: id(3), brand: "Example", name: "Benzoyl Peroxide Wash",
                               rawIngredientList: "Benzoyl Peroxide, Water, Glycerin"),
            ],
            pm: [
                RoutineProduct(id: id(4), brand: "Example", name: "Retinol Night Cream",
                               rawIngredientList: "Ingredients: Water, Retinol, Niacinamide"),
                RoutineProduct(id: id(5), brand: "Example", name: "Glycolic Toner",
                               rawIngredientList: "Water, Glycolic Acid, Salicylic Acid"),
            ]
        )
    }()

    static var sampleReport: AnalysisReport {
        AnalysisReport(result: analysis, profile: sampleDraft.profile, generatedAt: Date(timeIntervalSince1970: 1_788_600_000))
    }

    static func data(named name: String) -> Data {
        let bundle = Bundle(for: FixtureBundleMarker.self)
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            fatalError("Missing fixture \(name).json in \(bundle.bundlePath)")
        }
        return data
    }

    private static func load<T: Decodable>(_ name: String) -> T {
        do {
            return try APICoding.decoder.decode(T.self, from: data(named: name))
        } catch {
            fatalError("Fixture \(name).json does not decode as \(T.self): \(error)")
        }
    }
}
