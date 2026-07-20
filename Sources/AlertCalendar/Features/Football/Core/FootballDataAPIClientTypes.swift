import Foundation

extension FootballDataAPIClient {
    enum ClientError: LocalizedError, Sendable {
        case invalidResponse
        case unsuccessfulResponse(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The football feed returned an unreadable response."
            case .unsuccessfulResponse:
                return "The football feed is temporarily unavailable."
            }
        }
    }

    struct TeamResponse: Codable, Equatable, Sendable {
        let countryName: String?
        let isNational: Bool
        let logoURL: URL?
        let venueLocationText: String?
    }

    struct TeamCacheEntry: Codable, Sendable {
        let response: TeamResponse
        let fetchedAt: Date
    }

    struct ScoreboardPageCacheEntry {
        let matches: [FootballFixtureMatch]
        let fetchedAt: Date
    }

    struct SummaryRootCacheEntry {
        let root: [String: Any]
        let fetchedAt: Date
    }

    enum SummaryRootCacheRequirement {
        case any
        case minimumScorerCount(Int)
        case hasStatistics
    }

    struct SummarySnapshot {
        let statusState: FootballFixtureStatusState
        let statusText: String
        let statusDetailText: String?
        let statusPeriod: Int?
        let statusReliability: FootballFixtureStatusReliability
        let competitionNote: String?
        let seriesSummary: FootballFixtureSeriesSummary?
        let locationText: String?
        let actualStartDate: Date?
        let actualEndDate: Date?
        let homeScore: String
        let awayScore: String
        let homeYellowCards: Int
        let awayYellowCards: Int
        let homeRedCards: Int
        let awayRedCards: Int
        let officialWinner: FootballScoreSide?
        let homeShootoutScore: Int?
        let awayShootoutScore: Int?
        let pregameOutcomeProbabilities: FootballMatchOutcomeProbabilities?
        let outcomeProbabilities: FootballMatchOutcomeProbabilities?
    }
}
