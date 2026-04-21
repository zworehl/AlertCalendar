import AppKit
import Foundation
@testable import AlertCalendar

enum FootballTestData {
    static let defaultClubHomeTeam = clubTeam(
        id: "83",
        name: "Barcelona",
        abbreviation: "BAR",
        countryName: "Spain"
    )

    static let defaultClubAwayTeam = clubTeam(
        id: "132",
        name: "Bayern Munich",
        abbreviation: "BAY",
        countryName: "Germany"
    )

    static let defaultFriendlyHomeTeam = nationalTeam(
        id: "home-id",
        name: "Argentina",
        abbreviation: "ARG",
        countryName: "Argentina"
    )

    static let defaultFriendlyAwayTeam = nationalTeam(
        id: "away-id",
        name: "Guatemala",
        abbreviation: "GUA",
        countryName: "Guatemala"
    )

    static func clubTeam(
        id: String,
        name: String,
        abbreviation: String,
        countryName: String
    ) -> FootballTeamSummary {
        FootballTeamSummary(
            id: id,
            name: name,
            abbreviation: abbreviation,
            logoURL: nil,
            countryName: countryName,
            isNational: false
        )
    }

    static func nationalTeam(
        id: String,
        name: String,
        abbreviation: String,
        countryName: String
    ) -> FootballTeamSummary {
        FootballTeamSummary(
            id: id,
            name: name,
            abbreviation: abbreviation,
            logoURL: nil,
            countryName: countryName,
            isNational: true
        )
    }

    static func match(
        id: String,
        competitionSlug: String = "uefa.champions",
        competitionName: String = "UEFA Champions League",
        competitionStage: String? = nil,
        seasonSlug: String? = nil,
        competitionNote: String? = nil,
        seriesSummary: FootballFixtureSeriesSummary? = nil,
        locationText: String? = nil,
        startDate: Date = Date(timeIntervalSince1970: 1_720_000_000),
        actualStartDate: Date? = nil,
        statusState: FootballFixtureStatusState,
        statusText: String? = nil,
        statusDetailText: String? = nil,
        statusPeriod: Int? = nil,
        statusReliability: FootballFixtureStatusReliability = .reported,
        homeTeam: FootballTeamSummary = defaultClubHomeTeam,
        awayTeam: FootballTeamSummary = defaultClubAwayTeam,
        homeScore: String = "0",
        awayScore: String = "0",
        homeYellowCards: Int = 0,
        awayYellowCards: Int = 0,
        homeRedCards: Int = 0,
        awayRedCards: Int = 0
    ) -> FootballFixtureMatch {
        FootballFixtureMatch(
            id: id,
            competitionSlug: competitionSlug,
            competitionName: competitionName,
            competitionStage: competitionStage,
            seasonSlug: seasonSlug,
            competitionNote: competitionNote,
            seriesSummary: seriesSummary,
            competitionLogoURL: nil,
            locationText: locationText,
            startDate: startDate,
            actualStartDate: actualStartDate,
            statusState: statusState,
            statusText: statusText ?? (statusState == .inProgress ? "55'" : "7:00 PM"),
            statusDetailText: statusDetailText,
            statusPeriod: statusPeriod,
            statusReliability: statusReliability,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            homeScore: homeScore,
            awayScore: awayScore,
            homeYellowCards: homeYellowCards,
            awayYellowCards: awayYellowCards,
            homeRedCards: homeRedCards,
            awayRedCards: awayRedCards
        )
    }

    static func friendlyMatch(
        id: String,
        startDate: Date = Date(timeIntervalSince1970: 1_720_000_000),
        actualStartDate: Date? = nil,
        statusState: FootballFixtureStatusState,
        statusText: String? = nil,
        statusDetailText: String? = nil,
        statusPeriod: Int? = nil,
        statusReliability: FootballFixtureStatusReliability = .reported,
        locationText: String? = nil,
        homeTeam: FootballTeamSummary = defaultFriendlyHomeTeam,
        awayTeam: FootballTeamSummary = defaultFriendlyAwayTeam,
        homeScore: String = "0",
        awayScore: String = "0"
    ) -> FootballFixtureMatch {
        match(
            id: id,
            competitionSlug: "fifa.friendly",
            competitionName: "International Friendly",
            locationText: locationText,
            startDate: startDate,
            actualStartDate: actualStartDate,
            statusState: statusState,
            statusText: statusText,
            statusDetailText: statusDetailText,
            statusPeriod: statusPeriod,
            statusReliability: statusReliability,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            homeScore: homeScore,
            awayScore: awayScore
        )
    }

    static func upcomingFootballItem(
        for match: FootballFixtureMatch,
        endDate: Date? = nil,
        calendarID: String = "football-calendar",
        calendarName: String = "Football",
        calendarColor: NSColor = .systemOrange
    ) -> UpcomingItem {
        UpcomingItem(
            id: match.id,
            title: FootballFixtureFormatter.calendarTitle(for: match),
            date: match.startDate,
            endDate: endDate ?? match.startDate.addingTimeInterval(2 * 60 * 60),
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: match.locationText,
            meetingURL: nil,
            calendarID: calendarID,
            calendarName: calendarName,
            calendarColor: calendarColor,
            kind: .event,
            footballMatch: match,
            footballMenuBarDisplay: nil
        )
    }
}
