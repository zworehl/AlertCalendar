import XCTest
@testable import AlertCalendar

final class GamingCalendarClassifierTests: XCTestCase {
    func testRecognizesSupportedGamesWithoutInventingParticipants() {
        for game in EsportsCatalog.games {
            let result = GamingCalendarClassifier.classify(title: "\(game.displayName) World Cup final", notes: nil, url: nil, calendarName: "Games")
            XCTAssertEqual(result?.0, game)
            XCTAssertEqual(result?.1, .competitive)
        }
    }

    func testMaintenancePatchAndLaunchNeverBecomeMatches() {
        for title in ["League of Legends maintenance", "Rocket League patch", "Counter-Strike 2 lanzamiento", "StarCraft II update"] {
            XCTAssertEqual(GamingCalendarClassifier.classify(title: title, notes: "World Cup", url: nil, calendarName: "Esports")?.1, .gamingEvent)
        }
    }

    func testGamesWithoutVerifiedFixtureCoverageRemainOrdinaryCalendarEvents() {
        let titles = ["Age of Empires II World Cup final", "AoE2 Hidden Cup", "Red Bull Wololo final",
                      "GeoGuessr World League final", "Gran Turismo 7 Nations Cup", "GTWS Manufacturers Cup"]
        for title in titles {
            XCTAssertNil(GamingCalendarClassifier.classify(title: title, notes: nil, url: nil, calendarName: "Esports"), title)
        }
    }

    func testScoreTitleCanUseExplicitWorldsNotesAndOfficialGameSource() {
        let result = GamingCalendarClassifier.classify(title: "BLG 🇨🇳 3 - 1 🇰🇷 T1", notes: "Worlds semifinal\nhttps://lolesports.com/en-US/news", url: nil, calendarName: "Events")
        XCTAssertEqual(result?.0, .leagueOfLegends)
        XCTAssertEqual(result?.1, .competitive)
    }

    func testMeetingURLLeagueCodeAndAmbiguousGamesAreNotClassified() {
        XCTAssertNil(GamingCalendarClassifier.classify(title: "Team meeting", notes: "https://meet.google.com/abc-lpl-def", url: nil, calendarName: "Work"))
        XCTAssertNil(GamingCalendarClassifier.classify(title: "Team meeting https://meet.google.com/abc-lpl-def", notes: nil, url: nil, calendarName: "Work"))
        XCTAssertNil(GamingCalendarClassifier.classify(title: "League of Legends vs Rocket League tournament", notes: nil, url: nil, calendarName: "Games"))
        XCTAssertNil(GamingCalendarClassifier.classify(title: "lol this is funny", notes: nil, url: nil, calendarName: "Personal"))
    }
}
