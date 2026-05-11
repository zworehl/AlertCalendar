import XCTest
@testable import AlertCalendar

final class AlertCalendarStringTests: XCTestCase {
    func testTrimmedNonEmptyReturnsTrimmedContent() {
        XCTAssertEqual(
            AlertCalendarString.trimmedNonEmpty("  standup@example.com \n"),
            "standup@example.com"
        )
    }

    func testTrimmedNonEmptyDropsNilAndWhitespaceOnlyValues() {
        XCTAssertNil(AlertCalendarString.trimmedNonEmpty(nil))
        XCTAssertNil(AlertCalendarString.trimmedNonEmpty(" \n\t "))
    }
}
