import Foundation

protocol EsportsProviding: Sendable {
    func load(game: EsportsGame, from: Date, to: Date, trackedIDs: [Int]) async throws -> EsportsLoadResult
}

enum EsportsGame: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case leagueOfLegends, counterStrike2, rocketLeague, starCraft2
    // Legacy values remain decodable, but are not part of the supported catalog.
    case ageOfEmpires2, geoGuessr, granTurismo7

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leagueOfLegends: "League of Legends"
        case .counterStrike2: "Counter-Strike 2"
        case .rocketLeague: "Rocket League"
        case .starCraft2: "StarCraft II"
        case .ageOfEmpires2: "Age of Empires II"
        case .geoGuessr: "GeoGuessr"
        case .granTurismo7: "Gran Turismo 7"
        }
    }

    /// Public calendar filter values. Canonical match IDs use the game raw value.
    var providerSlug: String? {
        switch self {
        case .leagueOfLegends: "league-of-legends"
        case .counterStrike2: "cs-go"
        case .rocketLeague: "rl"
        case .starCraft2: "starcraft-2"
        case .ageOfEmpires2, .geoGuessr, .granTurismo7: nil
        }
    }
}

enum EsportsMatchStatus: String, Codable, Hashable, Sendable {
    case scheduled = "not_started"
    case running, finished, canceled, postponed, unknown
}

enum EsportsOpponentType: String, Codable, Hashable, Sendable {
    case team = "Team"
    case player = "Player"
}

struct EsportsOpponent: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let type: EsportsOpponentType
    var imageURL: URL? = nil
}

struct EsportsScore: Codable, Hashable, Sendable {
    let opponentID: Int
    let opponentType: EsportsOpponentType
    let score: Int
}

struct EsportsMatch: Identifiable, Codable, Hashable, Sendable {
    static let sourceAttribution = "Source: PandaScore"

    var id: String { "pandascore:\(game.rawValue):\(providerID)" }
    let providerID: Int
    let game: EsportsGame
    var name: String
    var competitionID: Int? = nil
    var competitionName: String = ""
    var opponents: [EsportsOpponent] = []
    var results: [EsportsScore] = []
    var status: EsportsMatchStatus = .unknown
    var scheduledAt: Date? = nil
    var beginAt: Date? = nil
    var endAt: Date? = nil
    var originalScheduledAt: Date? = nil
    var rescheduled: Bool = false
    var forfeit: Bool = false
    var winnerID: Int? = nil
    var winnerType: EsportsOpponentType? = nil
    var numberOfGames: Int? = nil
    var matchType: String? = nil
    var streamURL: URL? = nil
    var fetchedAt: Date = Date()
    var feedSourceURL: URL? = nil
    var feedSourceAttribution: String? = nil
    var feedCompetitionKey: String? = nil

    var sourceAttributionText: String {
        let attribution = feedSourceAttribution?.trimmingCharacters(in: .whitespacesAndNewlines)
        return attribution.flatMap { $0.isEmpty ? nil : $0 } ?? Self.sourceAttribution
    }

    var competitionKey: String? {
        if let key = feedCompetitionKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty { return key }
        return competitionID.map { "\(game.rawValue):\($0)" }
    }

    /// Results are keyed by participant identity, never by array position.
    func score(for opponent: EsportsOpponent) -> Int? {
        results.first { $0.opponentID == opponent.id && $0.opponentType == opponent.type }?.score
    }
}

struct EsportsLoadIssue: Equatable, Sendable {
    enum Kind: String, Sendable {
        case paginationLimit, invalidPagination, invalidPayload, requestFailed
        case rateLimited, unavailable, requestBudget
    }
    let kind: Kind
    var statusCode: Int? = nil
    var retryAt: Date? = nil
}

struct EsportsLoadResult: Sendable {
    let matches: [EsportsMatch]
    let isComplete: Bool
    let issues: [EsportsLoadIssue]
    let fetchedAt: Date
}

enum EsportsFeedError: Error, Equatable, Sendable {
    case unsupportedGame, invalidWindow
    case unavailable, invalidResponse, invalidPayload
    case unexpectedStatus(Int)
    case rateLimited(until: Date?)
    case retryDeferred(statusCode: Int?, until: Date)
    case requestBudget(until: Date)
    case networkUnavailable
}

enum EsportsCatalog {
    static let games: [EsportsGame] = [.leagueOfLegends, .counterStrike2, .rocketLeague, .starCraft2]
    static let providerGames = games

    static func supports(_ game: EsportsGame) -> Bool { games.contains(game) }
}

enum EsportsStreamURLPolicy {
    static func safeURL(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        let hosts = ["twitch.tv", "youtube.com", "youtu.be", "afreecatv.com", "sooplive.co.kr", "bilibili.com", "huya.com", "douyu.com"]
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) } ? url : nil
    }
}
