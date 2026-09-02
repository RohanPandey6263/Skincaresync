import Foundation

/// One decoder and one encoder for every API payload, so snake_case and date
/// handling are decided once.
enum APICoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = APIDates.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(text)")
            }
            return date
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

/// Pydantic emits `2026-09-01T09:12:03.000120Z` or `...+00:00`, with one to
/// six fractional digits. Foundation's ISO 8601 parser wants exactly three.
enum APIDates {
    // ISO8601DateFormatter is documented as thread-safe; it just is not marked Sendable.
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ text: String) -> Date? {
        var normalised = text
        // No timezone at all (naive datetime): treat as UTC.
        let hasZone = normalised.hasSuffix("Z") || normalised.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil
        if !hasZone { normalised += "Z" }
        // Trim or pad fractional seconds to exactly three digits.
        if let range = normalised.range(of: #"\.\d+"#, options: .regularExpression) {
            var digits = String(normalised[range].dropFirst())
            if digits.count > 3 { digits = String(digits.prefix(3)) }
            while digits.count < 3 { digits += "0" }
            normalised.replaceSubrange(range, with: "." + digits)
            return withFraction.date(from: normalised)
        }
        return plain.date(from: normalised)
    }
}
