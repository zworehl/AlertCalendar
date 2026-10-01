import Foundation

enum MusicPlaybackSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleMusic
    case youtubeMusic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .youtubeMusic: "YouTube Music"
        }
    }

    var systemImage: String {
        switch self {
        case .appleMusic: "music.note"
        case .youtubeMusic: "play.rectangle.fill"
        }
    }
}

struct AppleMusicStatusSettings: Codable, Equatable, Sendable {
    static let defaultEmojis = ["🎵", "🎶"]
    static let maximumEmojis = 10

    var isEnabled: Bool = false
    var connectionIDs: Set<String> = []
    var priority: Int = 6
    var source: MusicPlaybackSource = .appleMusic
    var emojis: [String] = defaultEmojis

    init(
        isEnabled: Bool = false,
        connectionIDs: Set<String> = [],
        priority: Int = 6,
        source: MusicPlaybackSource = .appleMusic,
        emojis: [String] = defaultEmojis
    ) {
        self.isEnabled = isEnabled
        self.connectionIDs = connectionIDs
        self.priority = priority
        self.source = source
        self.emojis = Self.normalizedEmojis(emojis)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case connectionIDs
        case priority
        case source
        case emojis
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        connectionIDs = try container.decodeIfPresent(Set<String>.self, forKey: .connectionIDs) ?? []
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 6
        source = try container.decodeIfPresent(MusicPlaybackSource.self, forKey: .source) ?? .appleMusic
        emojis = Self.normalizedEmojis(try container.decodeIfPresent([String].self, forKey: .emojis) ?? Self.defaultEmojis)
    }

    func normalized(validConnectionIDs: Set<String>) -> Self {
        var copy = self
        copy.connectionIDs.formIntersection(validConnectionIDs)
        copy.priority = SlackStatusPriority.normalized(priority)
        copy.emojis = Self.normalizedEmojis(emojis)
        return copy
    }

    private static func normalizedEmojis(_ values: [String]) -> [String] {
        let valid = Array(values.compactMap(SlackEmojiCatalog.normalizedEmoji).prefix(maximumEmojis))
        return valid.isEmpty ? defaultEmojis : valid
    }
}

enum SlackStatusPriority {
    static let values = Array(1 ... 10)

    static func normalized(_ value: Int) -> Int {
        min(10, max(1, value))
    }
}
