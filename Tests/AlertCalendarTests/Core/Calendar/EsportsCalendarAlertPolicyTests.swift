import EventKit
import XCTest
@testable import AlertCalendar

final class EsportsCalendarAlertPolicyTests: XCTestCase {
    func testManagedEsportsUsesItsOwnAlertPolicy() {
        let event = EKEvent(eventStore: EKEventStore())
        event.notes = "\(ManagedEsportsEventRecord.ownershipMarker)\npandascore:leagueOfLegends:42"
        XCTAssertFalse(CalendarMonitor.calendarAlertRuleApplies(CalendarAlertRule(calendarID: "events", scope: .allEvents), to: event))
    }

    func testAnUnmanagedProviderReferenceStillUsesTheCalendarRule() {
        let event = EKEvent(eventStore: EKEventStore())
        event.notes = "pandascore:leagueOfLegends:42"
        XCTAssertTrue(CalendarMonitor.calendarAlertRuleApplies(CalendarAlertRule(calendarID: "events", scope: .allEvents), to: event))
        event.notes = "League of Legends Worlds"
        XCTAssertTrue(CalendarMonitor.calendarAlertRuleApplies(CalendarAlertRule(calendarID: "events", scope: .allEvents), to: event))
    }
}
