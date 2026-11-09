import EventKit
import XCTest
@testable import AlertCalendar

@MainActor
final class EsportsCalendarAlertTests: XCTestCase {
    // These events are never saved, and no Calendar access or lookup is requested.
    private let eventStore = EKEventStore()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testZeroCreatesAnAlarmAtTheStartAndRequiresThatAlarmForMatching() {
        let content = content(lead: 0)
        let event = EKEvent(eventStore: eventStore)
        content.apply(to: event)

        XCTAssertEqual(event.alarms?.count, 1)
        XCTAssertEqual(event.alarms?.first?.relativeOffset, 0)
        XCTAssertTrue(content.stillMatches(event))
        event.alarms = nil
        XCTAssertFalse(content.stillMatches(event))
    }

    func testNegativeOneRemovesTheAlarmAndDoesNotMatchAnAtStartAlarm() {
        let content = content(lead: -1)
        let event = EKEvent(eventStore: eventStore)
        event.alarms = [EKAlarm(relativeOffset: 0)]
        content.apply(to: event)

        XCTAssertTrue(event.alarms?.isEmpty ?? true)
        XCTAssertTrue(content.stillMatches(event))
        event.alarms = [EKAlarm(relativeOffset: 0)]
        XCTAssertFalse(content.stillMatches(event))
    }

    func testCanceledAndPostponedMatchesSuppressAtStartAndAdvanceAlarms() {
        for status in [EsportsMatchStatus.canceled, .postponed] {
            for lead in [0, 15] {
                let content = content(lead: lead, status: status)
                let event = EKEvent(eventStore: eventStore)
                event.alarms = [EKAlarm(relativeOffset: -900)]
                content.apply(to: event)

                XCTAssertEqual(content.alertLeadMinutes, -1)
                XCTAssertTrue(event.alarms?.isEmpty ?? true)
                XCTAssertTrue(content.stillMatches(event))
            }
        }
    }

    private func content(lead: Int, status: EsportsMatchStatus = .scheduled) -> EsportsEventContent {
        let match = EsportsMatch(providerID: 1, game: .leagueOfLegends, name: "T1 vs GEN", status: status, scheduledAt: start)
        return EsportsEventContent(match: match, start: start, alertLeadMinutes: lead)
    }
}
