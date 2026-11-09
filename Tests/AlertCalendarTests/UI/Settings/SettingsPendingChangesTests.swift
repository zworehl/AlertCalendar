import Foundation
import XCTest
@testable import AlertCalendar

final class SettingsPendingChangesTests: XCTestCase {
    func testFootballFixtureAddStaysPendingUntilAppliedAndCanBeReverted() {
        let match = FootballTestData.match(id: "pending-add", statusState: .scheduled)
        var changes = SettingsPendingChanges()

        changes.toggleFootballFixture(match, persistedIsPresent: false)

        XCTAssertTrue(changes.footballFixtureIsPresent(match, persistedIsPresent: false))
        XCTAssertEqual(
            changes.footballFixtures[SettingsPendingChanges.footballFixtureKey(for: match)]?.mutation,
            .add
        )
        XCTAssertFalse(changes.isEmpty)

        changes.toggleFootballFixture(match, persistedIsPresent: false)

        XCTAssertFalse(changes.footballFixtureIsPresent(match, persistedIsPresent: false))
        XCTAssertTrue(changes.isEmpty)
    }

    func testFootballFixtureRemovalStaysPendingUntilAppliedAndCanBeReverted() {
        let match = FootballTestData.match(id: "pending-remove", statusState: .scheduled)
        var changes = SettingsPendingChanges()

        changes.toggleFootballFixture(match, persistedIsPresent: true)

        XCTAssertFalse(changes.footballFixtureIsPresent(match, persistedIsPresent: true))
        XCTAssertEqual(
            changes.footballFixtures[SettingsPendingChanges.footballFixtureKey(for: match)]?.mutation,
            .remove
        )

        changes.toggleFootballFixture(match, persistedIsPresent: true)

        XCTAssertTrue(changes.footballFixtureIsPresent(match, persistedIsPresent: true))
        XCTAssertTrue(changes.isEmpty)
    }

    func testGameSaleMutationUsesTheSamePendingAndRevertSemantics() {
        let sale = GameSaleEvent(
            store: .steam,
            sourceID: "pending-sale",
            title: "Pending Sale",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDateExclusive: Date(timeIntervalSince1970: 1_800_086_400),
            officialURL: URL(string: "https://store.steampowered.com")!
        )
        var changes = SettingsPendingChanges()

        changes.toggleGameSale(sale, persistedIsPresent: false)

        XCTAssertTrue(changes.gameSaleIsPresent(sale, persistedIsPresent: false))
        XCTAssertEqual(changes.gameSales[sale.id]?.mutation, .add)

        changes.toggleGameSale(sale, persistedIsPresent: false)

        XCTAssertFalse(changes.gameSaleIsPresent(sale, persistedIsPresent: false))
        XCTAssertTrue(changes.isEmpty)
    }

    func testSlackMutationsAreStagedAndDuplicateTokensAreDeduplicated() {
        let connection = SlackConnection(
            id: "team|user",
            teamID: "team",
            teamName: "Workspace",
            workspaceURLString: nil,
            userID: "user",
            userName: "person",
            userDisplayName: nil,
            emailAddress: nil,
            connectedAt: .distantPast,
            lastValidatedAt: .distantPast
        )
        var changes = SettingsPendingChanges()

        changes.stageSlackConnectionRemoval(connection)
        changes.stageSlackTokenConnection("xoxp-token")
        changes.stageSlackTokenConnection("xoxp-token")

        XCTAssertEqual(changes.slackConnectionsToRemove[connection.id], connection)
        XCTAssertEqual(changes.slackTokensToConnect, ["xoxp-token"])
        XCTAssertFalse(changes.isEmpty)
    }
}
