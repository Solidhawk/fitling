import Foundation

/// A text in several languages, as Postgres stores it in jsonb: {"nl": "Brood", "en": "Bread"}.
/// Used for content that comes from the database (products, recipes, exercises); interface
/// texts live in the String Catalog.
public struct LocalizedText: Hashable, Sendable {
    public var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public var isEmpty: Bool {
        values.values.allSatisfy(\.isEmpty)
    }

    /// The text in the first preferred language that has one. Falls back to English, then Dutch,
    /// then whatever language there is, so a product never shows up without a name.
    public func text(preferring languages: [String]) -> String {
        let wanted = languages.map(Self.languageCode) + ["en", "nl"]
        for code in wanted {
            if let text = values[code], !text.isEmpty { return text }
        }
        return values.sorted { $0.key < $1.key }.first { !$0.value.isEmpty }?.value ?? ""
    }

    /// "nl-NL" and "nl_BE" both count as "nl".
    private static func languageCode(_ identifier: String) -> String {
        String(identifier.lowercased().prefix { $0 != "-" && $0 != "_" })
    }
}

extension LocalizedText: Codable {
    public init(from decoder: any Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: String].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

extension LocalizedText {
    /// From the JSON the local store keeps. Unreadable data gives an empty text, not a crash:
    /// a product without a name is shown as such and can be fetched again.
    public init(json: Data) {
        self = (try? JSONDecoder().decode(LocalizedText.self, from: json)) ?? LocalizedText()
    }

    public var json: Data {
        (try? JSONEncoder().encode(self)) ?? Data("{}".utf8)
    }
}
