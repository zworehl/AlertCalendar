import Foundation

enum EsportsGame: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case leagueOfLegends, counterStrike2, rocketLeague, starCraft2
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

    /// These are API route prefixes, not interchangeable videogame slugs.
    var providerSlug: String? {
        switch self {
        case .leagueOfLegends: "lol"
        case .counterStrike2: "csgo"
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

    /// Results are keyed by participant identity, never by array position.
    func score(for opponent: EsportsOpponent) -> Int? {
        results.first { $0.opponentID == opponent.id && $0.opponentType == opponent.type }?.score
    }
}

struct EsportsLoadIssue: Equatable, Sendable {
    enum Kind: String, Sendable {
        case paginationLimit, invalidPagination, invalidPayload, requestFailed
        case rateLimited, unauthorized, unavailable, requestBudget
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

enum PandaScoreError: Error, Equatable, Sendable {
    case unsupportedGame, missingToken, invalidToken, invalidWindow
    case unauthorized, unavailable, invalidResponse, invalidPayload
    case unexpectedStatus(Int)
    case rateLimited(until: Date?)
    case retryDeferred(statusCode: Int?, until: Date)
    case requestBudget(until: Date)
    case networkUnavailable
}

enum EsportsCatalog {
    static let games = EsportsGame.allCases
    static var providerGames: [EsportsGame] { games.filter { $0.providerSlug != nil } }
}

enum EsportsStreamURLPolicy {
    static func safeURL(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        let hosts = ["twitch.tv", "youtube.com", "youtu.be", "afreecatv.com", "sooplive.co.kr", "bilibili.com", "huya.com", "douyu.com"]
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) } ? url : nil
    }
}
