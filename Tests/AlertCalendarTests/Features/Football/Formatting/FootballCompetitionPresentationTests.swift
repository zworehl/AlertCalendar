import XCTest
@testable import AlertCalendar

final class FootballCompetitionPresentationTests: FootballFixtureFormatterTestCase {
    func testCompetitionDetailTextCollapsesRedundantYearPrefixedStage() {
        XCTAssertEqual(
            FootballFixtureFormatter.competitionDetailText(
                competitionName: "International Friendly",
                competitionStage: "2026 International Friendly"
            ),
            "International Friendly"
        )
    }
    func testCompetitionDetailTextPreservesMeaningfulStage() {
        XCTAssertEqual(
            FootballFixtureFormatter.competitionDetailText(
                competitionName: "UEFA Champions League",
                competitionStage: "Quarterfinals"
            ),
            "UEFA Champions League • Quarterfinals"
        )
    }
    func testSharedCompetitionTitleUsesSharedCompetitionDetailWhenMatchesFullyAlign() {
        let matches = [
            FootballFixtureMatch(
                id: "shared-1",
                competitionSlug: "fifa.friendly",
                competitionName: "International Friendly",
                competitionStage: nil,
                competitionLogoURL: nil,
                locationText: nil,
                startDate: Date(timeIntervalSince1970: 1_720_000_000),
                statusState: .inProgress,
                statusText: "12'",
                homeTeam: FootballTeamSummary(
                    id: "usa",
                    name: "United States",
                    abbreviation: "USA",
                    logoURL: nil,
                    countryName: "United States",
                    isNational: true
                ),
                awayTeam: FootballTeamSummary(
                    id: "por",
                    name: "Portugal",
                    abbreviation: "POR",
                    logoURL: nil,
                    countryName: "Portugal",
                    isNational: true
                ),
                homeScore: "0",
                awayScore: "1"
            ),
            FootballFixtureMatch(
                id: "shared-2",
                competitionSlug: "fifa.friendly",
                competitionName: "International Friendly",
                competitionStage: nil,
                competitionLogoURL: nil,
                locationText: nil,
                startDate: Date(timeIntervalSince1970: 1_720_003_600),
                statusState: .inProgress,
                statusText: "23'",
                homeTeam: FootballTeamSummary(
                    id: "arg",
                    name: "Argentina",
                    abbreviation: "ARG",
                    logoURL: nil,
                    countryName: "Argentina",
                    isNational: true
                ),
                awayTeam: FootballTeamSummary(
                    id: "zam",
                    name: "Zambia",
                    abbreviation: "ZAM",
                    logoURL: nil,
                    countryName: "Zambia",
                    isNational: true
                ),
                homeScore: "1",
                awayScore: "0"
            ),
        ]

        XCTAssertEqual(
            FootballFixtureFormatter.sharedCompetitionTitle(for: matches),
            "International Friendly"
        )
    }
    func testSharedCompetitionTitleFallsBackToCompetitionNameWhenStagesDiffer() {
        let quarterfinal = FootballFixtureMatch(
            id: "knockout-1",
            competitionSlug: "uefa.champions",
            competitionName: "UEFA Champions League",
            competitionStage: "Quarterfinals",
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            statusText: "7:00 PM",
            homeTeam: FootballTeamSummary(
                id: "bar",
                name: "Barcelona",
                abbreviation: "BAR",
                logoURL: nil,
                countryName: "Spain",
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "bay",
                name: "Bayern Munich",
                abbreviation: "BAY",
                logoURL: nil,
                countryName: "Germany",
                isNational: false
            ),
            homeScore: "0",
            awayScore: "0"
        )
        let semifinal = FootballFixtureMatch(
            id: "knockout-2",
            competitionSlug: "uefa.champions",
            competitionName: "UEFA Champions League",
            competitionStage: "Semifinals",
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_003_600),
            statusState: .scheduled,
            statusText: "9:00 PM",
            homeTeam: FootballTeamSummary(
                id: "psg",
                name: "PSG",
                abbreviation: "PSG",
                logoURL: nil,
                countryName: "France",
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "int",
                name: "Internazionale",
                abbreviation: "INT",
                logoURL: nil,
                countryName: "Italy",
                isNational: false
            ),
            homeScore: "0",
            awayScore: "0"
        )

        XCTAssertEqual(
            FootballFixtureFormatter.sharedCompetitionTitle(for: [quarterfinal, semifinal]),
            "UEFA Champions League"
        )
    }
    func testSharedCompetitionTitleReturnsNilWhenCompetitionsDiffer() {
        let championsMatch = makeMatch(
            id: "mixed-1",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            competitionSlug: "uefa.champions"
        )
        let leagueMatch = FootballFixtureMatch(
            id: "mixed-2",
            competitionSlug: "eng.1",
            competitionName: "Premier League",
            competitionStage: nil,
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_003_600),
            statusState: .scheduled,
            statusText: "8:00 PM",
            homeTeam: FootballTeamSummary(
                id: "ars",
                name: "Arsenal",
                abbreviation: "ARS",
                logoURL: nil,
                countryName: "England",
                isNational: false
            ),
            awayTeam: FootballTeamSummary(
                id: "liv",
                name: "Liverpool",
                abbreviation: "LIV",
                logoURL: nil,
                countryName: "England",
                isNational: false
            ),
            homeScore: "0",
            awayScore: "0"
        )

        XCTAssertNil(FootballFixtureFormatter.sharedCompetitionTitle(for: [championsMatch, leagueMatch]))
    }
    func testManagedFixtureReferenceRoundTripsThroughURL() {
        let reference = ManagedFootballFixtureReference(
            matchID: "12345",
            competitionSlug: "uefa.champions"
        )

        let parsed = ManagedFootballFixtureReference.parse(from: reference.url)

        XCTAssertEqual(parsed, reference)
    }
    func testCalendarIdentityKeyIgnoresFlagsAndLiveScore() {
        XCTAssertEqual(
            FootballFixtureFormatter.calendarIdentityKey(fromCalendarTitle: "CAP 🇧🇷 1 - 0 🇧🇷 BOT"),
            "CAP|BOT"
        )
        XCTAssertEqual(
            FootballFixtureFormatter.calendarIdentityKey(fromCalendarTitle: "DOM 🇩🇴 - 🇨🇺 CUB"),
            "DOM|CUB"
        )
    }
    func testCalendarIdentityKeyForMatchUsesDisplayedTeamIdentifiers() {
        let match = FootballFixtureMatch(
            id: "match-identity",
            competitionSlug: "fifa.friendly",
            competitionName: "International Friendly",
            competitionStage: nil,
            competitionLogoURL: nil,
            locationText: nil,
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            statusState: .scheduled,
            statusText: "7:00 PM",
            homeTeam: FootballTeamSummary(
                id: "439",
                name: "Costa Rica",
                abbreviation: "CRC",
                logoURL: nil,
                countryName: "Costa Rica",
                isNational: true
            ),
            awayTeam: FootballTeamSummary(
                id: "1",
                name: "Palmeiras",
                abbreviation: "PALM",
                logoURL: nil,
                countryName: "Brazil",
                isNational: false
            ),
            homeScore: "0",
            awayScore: "0"
        )

        XCTAssertEqual(FootballFixtureFormatter.calendarIdentityKey(for: match), "CRC|PAL")
    }
    func testCompetitionPresetsCoverSupportedLeaguesAndUseConfiguredSuggestionWindow() {
        let expectedSlugs: Set<String> = [
            "eng.1",
            "esp.1",
            "bra.1",
            "ita.1",
            "ger.1",
            "fra.1",
            "por.1",
            "arg.1",
            "ned.1",
            "col.1",
            "crc.1",
            "mex.1",
            "usa.1",
            "concacaf.central.american.cup",
            "fifa.world",
            "fifa.friendly",
            "uefa.champions",
            "uefa.europa",
            "uefa.super_cup",
            "uefa.euro",
            "conmebol.america",
            "conmebol.libertadores",
            "fifa.cwc",
            "concacaf.gold",
            "caf.nations",
            "afc.asian.cup",
        ]

        XCTAssertEqual(Set(FootballCompetitionPreset.menuPresets.map(\.slug)), expectedSlugs)
        XCTAssertTrue(
            FootballCompetitionPreset.menuPresets.allSatisfy {
                $0.lookbackDays == FootballCompetitionPreset.suggestionWindowLookbackDays
                    && $0.lookaheadDays == FootballCompetitionPreset.suggestionWindowLookaheadDays
            }
        )
    }
    func testManagedFootballSuggestionWindowUsesFortyFiveDayLookbackAndNinetyDayLookahead() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_720_000_000)

        let insidePast = calendar.date(byAdding: .day, value: -45, to: now)!
        let insideFuture = calendar.date(byAdding: .day, value: 90, to: now)!
        let outsidePast = calendar.date(byAdding: .day, value: -46, to: now)!
        let outsideFuture = calendar.date(byAdding: .day, value: 91, to: now)!

        XCTAssertTrue(CalendarMonitor.isManagedFootballEventWithinSuggestionWindow(startDate: insidePast, now: now, calendar: calendar))
        XCTAssertTrue(CalendarMonitor.isManagedFootballEventWithinSuggestionWindow(startDate: insideFuture, now: now, calendar: calendar))
        XCTAssertFalse(CalendarMonitor.isManagedFootballEventWithinSuggestionWindow(startDate: outsidePast, now: now, calendar: calendar))
        XCTAssertFalse(CalendarMonitor.isManagedFootballEventWithinSuggestionWindow(startDate: outsideFuture, now: now, calendar: calendar))
    }}
