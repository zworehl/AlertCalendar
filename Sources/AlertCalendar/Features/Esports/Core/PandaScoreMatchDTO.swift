import Foundation

struct PandaScoreLossyArray<Value: Decodable>: Decodable {
    var values: [Value] = []
    var rejected = 0

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard (container.count ?? 0) <= 100 else { throw PandaScoreError.invalidPayload }
        while !container.isAtEnd {
            let item = try container.superDecoder()
            if let value = try? Value(from: item) { values.append(value) }
            else { rejected += 1 }
        }
    }
}

struct PandaScoreMatchDTO: Decodable {
    struct Context: Decodable {
        var id: Int?
        var name: String?
        var fullName: String?
        var slug: String?
    }
    struct Opponent: Decodable {
        struct Identity: Decodable {
            let id: Int
            let name: String
            var imageUrl: String?
        }
        let type: String
        let opponent: Identity
    }
    struct Result: Decodable {
        var teamId: Int?
        var playerId: Int?
        let score: Int
    }
    struct Stream: Decodable {
        let rawUrl: String
        var main: Bool?
        var official: Bool?
    }

    let id: Int
    let name: String
    let status: String
    var scheduledAt: Date?
    var beginAt: Date?
    var endAt: Date?
    var originalScheduledAt: Date?
    var rescheduled: Bool?
    var forfeit: Bool?
    var winnerId: Int?
    var winnerType: String?
    var numberOfGames: Int?
    var matchType: String?
    var league: Context?
    var serie: Context?
    var tournament: Context?
    var videogame: Context?
    var opponents: [Opponent]?
    var results: [Result]?
    var streamsList: [Stream]?

    func match(game: EsportsGame, fetchedAt: Date) throws -> EsportsMatch {
        guard id > 0, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PandaScoreError.invalidPayload }
        if let slug = videogame?.slug, !Self.accepts(slug: slug, for: game) { throw PandaScoreError.invalidPayload }
        let identities = try (opponents ?? []).map { opponent -> EsportsOpponent in
            guard opponent.opponent.id > 0, !opponent.opponent.name.isEmpty,
                  let type = EsportsOpponentType(rawValue: opponent.type) else { throw PandaScoreError.invalidPayload }
            return EsportsOpponent(id: opponent.opponent.id, name: opponent.opponent.name, type: type,
                                   imageURL: Self.webURL(opponent.opponent.imageUrl))
        }
        let scores = try (results ?? []).map { result -> EsportsScore in
            guard result.score >= 0 else { throw PandaScoreError.invalidPayload }
            if let id = result.teamId, id > 0, result.playerId == nil {
                return EsportsScore(opponentID: id, opponentType: .team, score: result.score)
            }
            if let id = result.playerId, id > 0, result.teamId == nil {
                return EsportsScore(opponentID: id, opponentType: .player, score: result.score)
            }
            throw PandaScoreError.invalidPayload
        }
        let streams = (streamsList ?? []).sorted {
            ($0.main == true ? 2 : ($0.official == true ? 1 : 0)) > ($1.main == true ? 2 : ($1.official == true ? 1 : 0))
        }
        return EsportsMatch(
            providerID: id, game: game, name: name,
            competitionID: league?.id ?? tournament?.id,
            competitionName: league?.id != nil ? (league?.name ?? "") : (tournament?.name ?? ""),
            opponents: identities, results: scores, status: EsportsMatchStatus(rawValue: status) ?? .unknown,
            scheduledAt: scheduledAt, beginAt: beginAt, endAt: endAt,
            originalScheduledAt: originalScheduledAt, rescheduled: rescheduled ?? false,
            forfeit: forfeit ?? false, winnerID: winnerId, winnerType: winnerType.flatMap(EsportsOpponentType.init(rawValue:)),
            numberOfGames: numberOfGames.flatMap { $0 > 0 ? $0 : nil }, matchType: matchType,
            streamURL: streams.lazy.compactMap { EsportsStreamURLPolicy.safeURL(Self.webURL($0.rawUrl)) }.first, fetchedAt: fetchedAt
        )
    }

    private static func accepts(slug: String, for game: EsportsGame) -> Bool {
        switch game {
        case .leagueOfLegends: ["league-of-legends", "lol"].contains(slug)
        case .counterStrike2: ["cs-go", "csgo", "counter-strike", "counter-strike-2"].contains(slug)
        case .rocketLeague: ["rl", "rocket-league"].contains(slug)
        case .starCraft2: ["starcraft-2", "starcraft-ii"].contains(slug)
        case .ageOfEmpires2, .geoGuessr, .granTurismo7: false
        }
    }

    private static func webURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased()),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw PandaScoreError.invalidPayload }
            return date
        }
        return decoder
    }
}
