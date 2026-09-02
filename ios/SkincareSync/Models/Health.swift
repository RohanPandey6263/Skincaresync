import Foundation

/// `GET /api/health`. Counts are null when the database is unreachable (503).
struct HealthStatus: Codable, Equatable, Sendable {
    var ok: Bool
    var database: String
    var ingredientCount: Int?
    var productCount: Int?
    var interactionCount: Int?
}
