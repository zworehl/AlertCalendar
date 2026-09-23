import XCTest
@testable import AlertCalendar

final class FootballTeamPresentationTests: XCTestCase {
    func testBroadcastIdentifiersPreserveProviderCodesAndDoNotInventMissingOnes() {
        for code in ["RMA", "ATM", "MNC", "MAN", "REMO", "CRC"] {
            XCTAssertEqual(FootballFixtureFormatter.normalizedAbbreviation(" \(code.lowercased()) ", fallbackName: "Team"), code)
        }
        XCTAssertEqual(FootballFixtureFormatter.normalizedAbbreviation("", fallbackName: "Manchester United"), "Manchester United")
    }

    func testTeamNamesPreserveWordsAccentsAndNumbers() {
        for name in ["Costa Rica", "Newcastle United", "Atlético de Madrid", "Schalke 04", "1860 Munich"] {
            let team = FootballTeamSummary(
                id: "team", name: " \(name)\n", abbreviation: "ABC", logoURL: nil,
                countryName: nil, isNational: false
            )
            XCTAssertEqual(FootballFixtureFormatter.teamDisplayName(for: team), name)
        }
    }

    func testMissingNamesAndUnresolvedTeamsKeepSafeFallbacks() {
        let unnamed = FootballTeamSummary(
            id: "club", name: " \n", abbreviation: "PALM", logoURL: nil,
            countryName: "Brazil", isNational: false
        )
        let unresolved = FootballTeamSummary(
            id: "slot", name: "Group A Winner", abbreviation: "GRO", logoURL: nil,
            countryName: nil, isNational: true
        )
        XCTAssertEqual(FootballFixtureFormatter.teamDisplayName(for: unnamed), "PALM")
        XCTAssertEqual(FootballFixtureFormatter.teamDisplayName(for: unresolved), "TBD")
    }

    func testCalendarRecoveryRecognizesOldAndNewTitlesAfterTheScoreChanges() throws {
        let match = FootballTestData.match(id: "live", statusState: .inProgress, homeScore: "2", awayScore: "1")
        let identities = FootballFixtureFormatter.calendarIdentityKeys(for: match)

        for title in [
            "BAR 🇪🇸 - 🇩🇪 BAY",
            "BAR 🇪🇸 1 - 0 🇩🇪 BAY",
            "Barcelona 🇪🇸 - 🇩🇪 Bayern Munich",
            "Barcelona 🇪🇸 1 - 0 🇩🇪 Bayern Munich",
        ] {
            XCTAssertTrue(FootballFixtureFormatter.looksLikeFootballCalendarTitle(title), title)
            let key = try XCTUnwrap(FootballFixtureFormatter.calendarIdentityKey(fromCalendarTitle: title))
            XCTAssertTrue(identities.contains(key), title)
        }
    }

    func testCalendarIdentityPreservesTeamNumbersAndHandlesFlagFallbacks() {
        for title in [
            "Schalke 04 🇩🇪 - 🇩🇪 1860 Munich",
            "Schalke 04 🇩🇪 2 - 1 🇩🇪 1860 Munich",
            "Schalke 04 🏳️ - 🏳️ 1860 Munich",
        ] {
            XCTAssertTrue(FootballFixtureFormatter.looksLikeFootballCalendarTitle(title), title)
            XCTAssertEqual(
                FootballFixtureFormatter.calendarIdentityKey(fromCalendarTitle: title),
                "SCHALKE04|1860MUNICH"
            )
        }
    }

    func testCalendarDetectionDoesNotDependOnUppercaseAbbreviations() {
        XCTAssertTrue(FootballFixtureFormatter.looksLikeFootballCalendarTitle("Peru 🇵🇪 - 🇨🇱 Chile"))
        XCTAssertTrue(FootballFixtureFormatter.looksLikeFootballCalendarTitle("TBD 🏴 - 🏴 TBD"))
        XCTAssertFalse(FootballFixtureFormatter.looksLikeFootballCalendarTitle("Trip 🇵🇪 - Planning"))
        XCTAssertFalse(FootballFixtureFormatter.looksLikeFootballCalendarTitle("🇵🇪 - 🇨🇱"))
        XCTAssertFalse(FootballFixtureFormatter.looksLikeFootballCalendarTitle("Design - Review"))
    }
}
