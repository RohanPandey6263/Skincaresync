import Foundation

enum SkinType: String, Codable, CaseIterable, Sendable, Identifiable {
    case normal, oily, dry, combination, sensitive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .oily: "Oily"
        case .dry: "Dry"
        case .combination: "Combination"
        case .sensitive: "Sensitive"
        }
    }
}

enum Concern: String, Codable, CaseIterable, Sendable, Identifiable {
    case acne, rosacea, hyperpigmentation, eczema
    case antiAging = "anti-aging"
    case dehydration

    var id: String { rawValue }

    var label: String {
        switch self {
        case .acne: "Acne"
        case .rosacea: "Rosacea"
        case .hyperpigmentation: "Hyperpigmentation"
        case .eczema: "Eczema"
        case .antiAging: "Anti-aging"
        case .dehydration: "Dehydration"
        }
    }
}

struct SkinProfile: Codable, Equatable, Sendable {
    var skinType: SkinType = .normal
    var concerns: [Concern] = []

    var summary: String {
        let concernText = concerns.isEmpty ? "no concerns selected" : concerns.map(\.label).joined(separator: ", ")
        return "\(skinType.label) skin, \(concernText)"
    }
}

enum RoutineSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case am, pm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .am: "Morning"
        case .pm: "Evening"
        }
    }

    var symbol: String {
        switch self {
        case .am: "sun.max"
        case .pm: "moon"
        }
    }
}

/// A product the user has placed in a routine. Only durable data lives here;
/// lookup progress is transient state on the view model.
struct RoutineProduct: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var brand: String = ""
    var name: String = ""
    var code: String?
    var rawIngredientList: String = ""
    var imageUrl: String?
    var productUrl: String?
    var source: String?

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedBrand: String { brand.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedIngredients: String { rawIngredientList.trimmingCharacters(in: .whitespacesAndNewlines) }

    var hasIngredients: Bool { !trimmedIngredients.isEmpty }

    /// Ready for analysis: the backend requires a name and a non-blank list.
    var isReady: Bool { !trimmedName.isEmpty && hasIngredients }

    var label: String {
        [trimmedBrand, trimmedName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var ingredientCount: Int { IngredientCounter.count(rawIngredientList) }

    init(id: UUID = UUID(), brand: String = "", name: String = "", code: String? = nil,
         rawIngredientList: String = "", imageUrl: String? = nil, productUrl: String? = nil, source: String? = nil) {
        self.id = id
        self.brand = brand
        self.name = name
        self.code = code
        self.rawIngredientList = rawIngredientList
        self.imageUrl = imageUrl
        self.productUrl = productUrl
        self.source = source
    }

    init(match: ProductMatch, id: UUID = UUID()) {
        self.init(id: id, brand: match.brand, name: match.name, code: match.code,
                  rawIngredientList: match.rawIngredientList, imageUrl: match.imageUrl,
                  productUrl: match.productUrl, source: match.source)
    }

    /// Copies the looked-up product's data onto this row, keeping the row identity.
    mutating func apply(_ match: ProductMatch) {
        brand = match.brand
        name = match.name
        code = match.code
        rawIngredientList = match.rawIngredientList
        imageUrl = match.imageUrl
        productUrl = match.productUrl
        source = match.source
    }
}

/// Everything the Routine tab persists between launches.
struct RoutineDraft: Codable, Equatable, Sendable {
    var profile = SkinProfile()
    var am: [RoutineProduct] = []
    var pm: [RoutineProduct] = []

    static let empty = RoutineDraft()

    subscript(slot: RoutineSlot) -> [RoutineProduct] {
        get { slot == .am ? am : pm }
        set { if slot == .am { am = newValue } else { pm = newValue } }
    }

    var allProducts: [RoutineProduct] { am + pm }
}

/// Mirrors `parser.tokenize_inci`: commas split ingredients only at parenthesis
/// depth zero, so "Aqua (Water, Eau), Glycerin" counts as two.
enum IngredientCounter {
    static func count(_ raw: String) -> Int {
        guard !raw.isEmpty else { return 0 }
        var text = raw
        let prefix = #"^\s*(ingredients|ingredient list|inci|active ingredients)\s*:\s*"#
        if let regex = try? NSRegularExpression(pattern: prefix, options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        var count = 0
        var depth = 0
        var current = ""
        for character in text {
            switch character {
            case "(":
                depth += 1
                current.append(character)
            case ")":
                depth = max(0, depth - 1)
                current.append(character)
            case "," where depth == 0:
                if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
                current = ""
            default:
                current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        return count
    }
}

// MARK: - Readiness and request mapping

/// Why a routine can or cannot be analysed yet, in words the UI can show.
struct RoutineReadiness: Equatable, Sendable {
    static let requiredProducts = 2

    var readyCount: Int
    /// Products present in the draft that lack a name or an ingredient list.
    var incomplete: [(slot: RoutineSlot, position: Int, product: RoutineProduct)]

    var canAnalyze: Bool { readyCount >= Self.requiredProducts }

    /// One sentence explaining what is still needed, or nil when ready.
    var explanation: String? {
        if canAnalyze {
            return incomplete.isEmpty
                ? nil
                : "\(incomplete.count) product\(incomplete.count == 1 ? "" : "s") without an ingredient list will be skipped."
        }
        let missing = Self.requiredProducts - readyCount
        if let first = incomplete.first {
            let name = first.product.trimmedName.isEmpty ? "Product \(first.position)" : first.product.trimmedName
            let need = first.product.trimmedName.isEmpty ? "a name and an ingredient list" : "an ingredient list"
            return "\(name) in \(first.slot.title) needs \(need). Add \(missing) more ready product\(missing == 1 ? "" : "s") to analyze."
        }
        return "Add at least \(Self.requiredProducts) products with ingredient lists across Morning and Evening. \(readyCount) of \(Self.requiredProducts) ready."
    }

    static func == (lhs: RoutineReadiness, rhs: RoutineReadiness) -> Bool {
        lhs.readyCount == rhs.readyCount
            && lhs.incomplete.map(\.product.id) == rhs.incomplete.map(\.product.id)
    }

    init(draft: RoutineDraft) {
        var ready = 0
        var incomplete: [(slot: RoutineSlot, position: Int, product: RoutineProduct)] = []
        for slot in RoutineSlot.allCases {
            for (index, product) in draft[slot].enumerated() {
                if product.isReady {
                    ready += 1
                } else {
                    incomplete.append((slot, index + 1, product))
                }
            }
        }
        readyCount = ready
        self.incomplete = incomplete
    }
}

extension AnalyzeRequest {
    /// Builds the request from a draft, sending only products the backend will
    /// accept (a name and a non-blank ingredient list).
    init(draft: RoutineDraft) {
        skinProfile = SkinProfilePayload(
            skinType: draft.profile.skinType.rawValue,
            concerns: draft.profile.concerns.map(\.rawValue)
        )
        amProducts = draft.am.filter(\.isReady).map(ProductPayload.init(product:))
        pmProducts = draft.pm.filter(\.isReady).map(ProductPayload.init(product:))
    }
}

extension AnalyzeRequest.ProductPayload {
    init(product: RoutineProduct) {
        brand = product.trimmedBrand
        name = product.trimmedName
        rawIngredientList = product.trimmedIngredients
    }
}

/// A completed analysis together with the inputs that produced it.
struct AnalysisReport: Equatable, Sendable {
    var result: AnalysisResult
    var profile: SkinProfile
    var generatedAt: Date
}
