import Foundation
import XCTest
@testable import AlertCalendar

final class FootballDataAPIClientStatusParsingTests: FootballDataAPIClientTestCase {
    func testParseEventDateSupportsESPNValuesWithoutSeconds() {
        let date = FootballDataAPIClient.parseEventDate("2026-02-25T22:00Z")

        XCTAssertNotNil(date)
    }
    func testParseEventDateSupportsESPNValuesWithSeconds() {
        let date = FootballDataAPIClient.parseEventDate("2026-02-25T22:00:00Z")

        XCTAssertNotNil(date)
    }
    func testPreferredStatusTextKeepsInterruptedShortDetailOverMinuteDetail() {
        let text = FootballDataAPIClient.preferredStatusText(
            shortDetail: "Delay",
            detail: "11'",
            displayClock: "11:00"
        )

        XCTAssertEqual(text, "Delay")
    }

    func testPreferredStatusTextUsesHydrationDetailOverMinuteShortDetail() {
        let text = FootballDataAPIClient.preferredStatusText(
            shortDetail: "27'",
            detail: "Hydration break",
            displayClock: "27:00"
        )

        XCTAssertEqual(text, "Hydration break")
    }

    func testSupplementalStatusTextPreservesMinuteWhenInterruptedShortDetailWins() {
        let text = FootballDataAPIClient.supplementalStatusText(
            preferredStatusText: "Delay",
            detail: "11'",
            displayClock: "11:00"
        )

        XCTAssertEqual(text, "11'")
    }

    func testSupplementalStatusTextPreservesMinuteWhenHydrationDetailWins() {
        let text = FootballDataAPIClient.supplementalStatusText(
            preferredStatusText: "Hydration break",
            detail: "Hydration break",
            displayClock: "27'"
        )

        XCTAssertEqual(text, "27'")
    }

    func testSupplementalStatusTextUsesDisplayClockWhenInterruptedDetailRepeatsDelay() {
        let text = FootballDataAPIClient.supplementalStatusText(
            preferredStatusText: "Delay",
            detail: "Delayed",
            displayClock: "45'+3'"
        )

        XCTAssertEqual(text, "45'+3'")
    }
}
