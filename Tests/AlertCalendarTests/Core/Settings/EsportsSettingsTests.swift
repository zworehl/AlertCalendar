import Foundation
import XCTest
@testable import AlertCalendar

@MainActor
final class EsportsSettingsTests: XCTestCase {
    func testExistingInstallationLoadsSafePilotDefaults() {
        let suite = "test.esports.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()
        let settings = store.load().esports
        XCTAssertEqual(settings.providerGames, [.leagueOfLegends])
        XCTAssertTrue(settings.autoAddCompetitionIDs.isEmpty)
        XCTAssertTrue(settings.targetCalendarID.isEmpty)
        defaults.set(Data("broken".utf8), forKey: DefaultsKeys.esportsSettings)
        XCTAssertEqual(store.load().esports, .defaults)
    }

    func testUnknownFutureGameDoesNotDiscardKnownPreferences() throws {
        let json = Data(#"{"providerGames":["leagueOfLegends","futureGame"],"targetCalendarID":"calendar"}"#.utf8)
        let settings = try JSONDecoder().decode(EsportsSettings.self, from: json)
        XCTAssertEqual(settings.providerGames, [.leagueOfLegends])
        XCTAssertEqual(settings.targetCalendarID, "calendar")
        XCTAssertTrue(settings.autoAddCompetitionIDs.isEmpty)
    }

    func testSettingsAreNormalizedAndPersistedWithoutCredentials() {
        let suite = "test.esports.roundtrip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()
        var settings = store.load()
        settings.esports.providerGames = [.leagueOfLegends, .geoGuessr]
        settings.esports.targetCalendarID = " calendar "
        settings.esports.autoAddCompetitionIDs = ["", " tournament "]
        settings.esports.lookaheadDays = 900
        settings.esports.lookbackDays = -50
        settings.esports.alertLeadMinutes = -15
        store.save(settings)
        let loaded = store.load().esports
        XCTAssertEqual(loaded.providerGames, [.leagueOfLegends])
        XCTAssertEqual(loaded.targetCalendarID, "calendar")
        XCTAssertEqual(loaded.autoAddCompetitionIDs, ["tournament"])
        XCTAssertEqual(loaded.lookaheadDays, 180)
        XCTAssertEqual(loaded.lookbackDays, 0)
        XCTAssertEqual(loaded.alertLeadMinutes, -1)
        let persisted = String(decoding: defaults.data(forKey: DefaultsKeys.esportsSettings)!, as: UTF8.self)
        XCTAssertFalse(persisted.lowercased().contains("token"))
    }

    func testDraftStagesAndRevertsEsportsChangesIndependently() {
        let current = AppSettings.defaults
        var draft = SettingsDraft(settings: current)
        draft.esports.providerGames = [.counterStrike2]
        draft.esports.autoAddCompetitionIDs = ["cs-league"]
        draft.esports.targetCalendarID = "destination"
        XCTAssertEqual(current.esports, .defaults)
        let applied = draft.applied(to: current, availableEventCalendarIDs: ["destination"])
        XCTAssertEqual(applied.esports.providerGames, [.counterStrike2])
        XCTAssertEqual(applied.esports.autoAddCompetitionIDs, ["cs-league"])
        draft = SettingsDraft(settings: current)
        XCTAssertEqual(draft.esports, .defaults)
    }

    func testTogglingStagedMatchTwiceCancelsWithoutWriting() {
        let match = EsportsMatch(providerID: 42, game: .leagueOfLegends, name: "Final")
        var pending = SettingsPendingChanges()
        pending.toggleEsportsMatch(match, persistedIsPresent: false)
        XCTAssertFalse(pending.isEmpty)
        XCTAssertTrue(pending.esportsMatchIsPresent(match, persistedIsPresent: false))
        pending.toggleEsportsMatch(match, persistedIsPresent: false)
        XCTAssertTrue(pending.isEmpty)
    }
}
