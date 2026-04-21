import XCTest
@testable import AlertCalendar

class FootballFixtureFormatterTestCase: XCTestCase {
    func makeMatch(
        id: String,
        startDate: Date,
        actualStartDate: Date? = nil,
        statusState: FootballFixtureStatusState,
        statusText: String? = nil,
        statusDetailText: String? = nil,
        statusPeriod: Int? = nil,
        statusReliability: FootballFixtureStatusReliability = .reported,
        competitionSlug: String = "uefa.champions",
        seasonSlug: String? = nil,
        competitionNote: String? = nil,
        seriesSummary: FootballFixtureSeriesSummary? = nil,
        homeTeam: FootballTeamSummary? = nil,
        awayTeam: FootballTeamSummary? = nil,
        homeScore: String = "0",
        awayScore: String = "0"
    ) -> FootballFixtureMatch {
        FootballTestData.match(
            id: id,
            competitionSlug: competitionSlug,
            competitionName: "UEFA Champions League",
            competitionStage: nil,
            seasonSlug: seasonSlug,
            competitionNote: competitionNote,
            seriesSummary: seriesSummary,
            locationText: nil,
            startDate: startDate,
            actualStartDate: actualStartDate,
            statusState: statusState,
            statusText: statusText ?? (statusState == .inProgress ? "55'" : "7:00 PM"),
            statusDetailText: statusDetailText,
            statusPeriod: statusPeriod,
            statusReliability: statusReliability,
            homeTeam: homeTeam ?? FootballTestData.defaultClubHomeTeam,
            awayTeam: awayTeam ?? FootballTestData.defaultClubAwayTeam,
            homeScore: homeScore,
            awayScore: awayScore
        )
    }
}
