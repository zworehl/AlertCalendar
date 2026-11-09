import Foundation

/// Standard emoji recognized by Slack. The bundled catalog is derived from
/// iamcal/emoji-data, which Slack cites as its standard emoji source.
enum SlackEmojiCatalog {
    private struct Catalog: Decodable {
        let unicode: [String: String]
        let aliases: [String: String]
    }

    private static let catalog: Catalog = {
        guard let url = Bundle.module.url(forResource: "SlackEmojiCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else {
            return Catalog(unicode: ["🎵": "🎵", "🎶": "🎶"], aliases: ["musical_note": "🎵", "notes": "🎶"])
        }
        return catalog
    }()

    static func normalizedEmoji(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let emoji = catalog.unicode[value] { return emoji }
        guard value.count > 2, value.first == ":", value.last == ":" else { return nil }
        return catalog.aliases[String(value.dropFirst().dropLast()).lowercased()]
    }
}
