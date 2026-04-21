import XCTest
@testable import AlertCalendar

final class FootballCalendarAutomationTests: XCTestCase {
    func testCalendarRevealScriptIncludesEscapedEventIdentifierAndLoopsCalendars() {
        let script = CalendarMonitor.calendarRevealScript(
            eventUID: #"event-"uid"\id"#
        )

        XCTAssertTrue(script.contains("repeat with targetCalendar in every calendar"))
        XCTAssertTrue(script.contains(#"uid is "event-\"uid\"\\id""#))
        XCTAssertTrue(script.contains("show targetEvent"))
    }

    func testAppleScriptStringLiteralEscapesQuotesAndBackslashes() {
        let literal = CalendarMonitor.appleScriptStringLiteral(#"value "quoted" \ path"#)

        XCTAssertEqual(literal, #""value \"quoted\" \\ path""#)
    }
}
