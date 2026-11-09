import XCTest
@testable import AlertCalendar

final class FootballFixtureSchedulingTextTests: FootballFixtureFormatterTestCase {
    func testKickoffStatusTextUsesWeekdayWhenFixtureIsWithinAWeek() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let startDate = calendar.date(byAdding: .day, value: 3, to: now)!

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE h:mm a")

        XCTAssertEqual(
            CalendarMonitor.footballKickoffStatusText(
                for: startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            formatter.string(from: startDate)
        )
    }
    func testKickoffStatusTextUsesTodayWhenFixtureIsLaterTheSameDay() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let startDate = calendar.date(byAdding: .hour, value: 5, to: now)!

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("h:mm a")

        XCTAssertEqual(
            CalendarMonitor.footballKickoffStatusText(
                for: startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Today \(formatter.string(from: startDate))"
        )
    }
    func testKickoffStatusTextUsesTomorrowWhenFixtureIsNextDay() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let startDate = calendar.date(byAdding: .day, value: 1, to: now)!

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("h:mm a")

        XCTAssertEqual(
            CalendarMonitor.footballKickoffStatusText(
                for: startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Tomorrow \(formatter.string(from: startDate))"
        )
    }
    func testKickoffStatusTextUsesDateWhenFixtureIsMoreThanAWeekAway() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let startDate = calendar.date(byAdding: .day, value: 10, to: now)!

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d h:mm a")

        XCTAssertEqual(
            CalendarMonitor.footballKickoffStatusText(
                for: startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            formatter.string(from: startDate)
        )
    }
    func testStartedStatusTextUsesStartedPrefixForFinishedFixtures() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let startDate = calendar.date(byAdding: .hour, value: -3, to: now)!

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("h:mm a")

        XCTAssertEqual(
            CalendarMonitor.footballStartedStatusText(
                for: startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Started \(formatter.string(from: startDate))"
        )
    }
    func testDelayedLiveFixtureUsesStartedScheduleText() {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let startDate = calendar.date(byAdding: .hour, value: -1, to: now)!
        let match = makeMatch(
            id: "delayed-live-schedule",
            startDate: startDate,
            statusState: .inProgress,
            statusText: "Delay",
            statusDetailText: "45'+3'",
            homeScore: "1",
            awayScore: "0"
        )

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("h:mm a")

        XCTAssertEqual(
            CalendarMonitor.footballScheduleText(
                for: match,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Started \(formatter.string(from: startDate))"
        )
    }
}
