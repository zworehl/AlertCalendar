import AppKit
import Foundation
import XCTest
@testable import AlertCalendar

final class FootballSectionMatchResolutionTests: AlertCalendarModelTestCase {
    func testResolvedFootballSectionMatchesPrefersCachedEnrichedMatch() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let scheduledStart = now.addingTimeInterval(-10 * 60)
        let actualKickoff = now.addingTimeInterval(-3 * 60)
        let rawMatch = makeFootballMatch(
            id: "match-1",
            startDate: scheduledStart,
            actualStartDate: nil,
            statusState: .inProgress,
            statusText: "15'"
        )
        let cachedMatch = makeFootballMatch(
            id: "match-1",
            startDate: scheduledStart,
            actualStartDate: actualKickoff,
            statusState: .inProgress,
            statusText: "15'"
        )

        let resolved = CalendarMonitor.resolvedFootballSectionMatches(
            [rawMatch],
            cachedMatchesByID: [rawMatch.id: cachedMatch],
            now: now
        )

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.actualStartDate, actualKickoff)
    }
    func testResolvedFootballSectionMatchesExcludeFixturesWithUnknownParticipants() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let knownMatch = makeFootballMatch(
            id: "known",
            startDate: now.addingTimeInterval(60 * 60),
            actualStartDate: nil,
            statusState: .scheduled,
            statusText: "7:00 PM"
        )
        let unknownMatch = FootballFixtureMatch(
            id: "unknown",
            competitionSlug: "uefa.champions",
            competitionName: "UEFA Champions League",
            competitionStage: "Semifinals",
            competitionLogoURL: nil,
            locationText: nil,
            startDate: now.addingTimeInterval(30 * 60),
            statusState: .scheduled,
            statusText: "TBD",
            homeTeam: FootballTeamSummary(
                id: "17631",
                name: "Quarterfinal 1 Winner",
                abbreviation: "QFW1",
                logoURL: nil,
                countryName: nil,
                isNational: false
            ),
            awayTeam: knownMatch.awayTeam,
            homeScore: "0",
            awayScore: "0"
        )

        let resolved = CalendarMonitor.resolvedFootballSectionMatches(
            [unknownMatch, knownMatch],
            cachedMatchesByID: [:],
            now: now
        )

        XCTAssertEqual(resolved.map(\.id), ["known"])
    }
    func testResolvedFootballSectionMatchesExcludeFixturesWithCompactPlaceholderSlots() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let knownMatch = makeFootballMatch(
            id: "known",
            startDate: now.addingTimeInterval(60 * 60),
            actualStartDate: nil,
            statusState: .scheduled,
            statusText: "7:00 PM"
        )
        let placeholderMatch = FootballFixtureMatch(
            id: "placeholder",
            competitionSlug: "fifa.world",
            competitionName: "FIFA World Cup",
            competitionStage: "Round of 16",
            competitionLogoURL: nil,
            locationText: nil,
            startDate: now.addingTimeInterval(30 * 60),
            statusState: .scheduled,
            statusText: "TBD",
            homeTeam: FootballTeamSummary(
                id: "ga2",
                name: "GA2",
                abbreviation: "GA2",
                logoURL: nil,
                countryName: nil,
                isNational: true
            ),
            awayTeam: FootballTeamSummary(
                id: "rd3",
                name: "RD3",
                abbreviation: "RD3",
                logoURL: nil,
                countryName: nil,
                isNational: true
            ),
            homeScore: "0",
            awayScore: "0"
        )

        let resolved = CalendarMonitor.resolvedFootballSectionMatches(
            [placeholderMatch, knownMatch],
            cachedMatchesByID: [:],
            now: now
        )

        XCTAssertEqual(resolved.map(\.id), ["known"])
    }}
