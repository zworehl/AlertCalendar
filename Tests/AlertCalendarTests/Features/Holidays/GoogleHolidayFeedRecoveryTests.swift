import Foundation
import XCTest
@testable import AlertCalendar

final class GoogleHolidayFeedRecoveryTests: IntegrationHTTPTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPartialFailurePersistsSuccessfulCountriesAndRetriesOnlyFailedCountryAfterRelaunch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let store = GoogleHolidayFeedCacheStore(fileURL: folder.appendingPathComponent("holidays.json"))
        let log = IntegrationRequestLog()
        let first = GoogleHolidayFeedClient(session: session { request in
            let country = request.url!.absoluteString.contains("en.cr") ? "CR" : "US"
            log.record(country)
            return self.reply(request, status: country == "US" ? 404 : 200, body: self.ics(country))
        }, cacheStore: store)
        let partial = try await first.fetchHolidayLoadResult(countryIDs: ["CR", "US"], now: now)
        XCTAssertEqual(partial.failedCountryIDs, ["US"])
        XCTAssertEqual(partial.events.map(\.countryID), ["CR"])
        XCTAssertEqual(Set(store.load(now: now).countries.keys), ["CR"])

        let restored = GoogleHolidayFeedClient(session: session { request in
            let country = request.url!.absoluteString.contains("en.cr") ? "CR" : "US"
            log.record(country)
            return self.reply(request, body: self.ics(country))
        }, cacheStore: store)
        let recovered = try await restored.fetchHolidayLoadResult(countryIDs: ["CR", "US"], now: now.addingTimeInterval(61))
        XCTAssertTrue(recovered.isComplete)
        XCTAssertEqual(Set(recovered.events.map(\.countryID)), ["CR", "US"])
        XCTAssertEqual(log.count("CR"), 1)
        XCTAssertEqual(log.count("US"), 2)
    }

    func testFailedCountryRetainsValidatedCacheAlongsideUpdatedHealthyCountry() async throws {
        let log = IntegrationRequestLog()
        let client = GoogleHolidayFeedClient(session: session { request in
            let country = request.url!.absoluteString.contains("en.cr") ? "CR" : "US"
            let attempt = log.record(country)
            return self.reply(request, status: country == "US" && attempt > 1 ? 404 : 200,
                              body: self.ics(country, title: attempt > 1 ? "Updated" : "Original"))
        })
        _ = try await client.fetchHolidayLoadResult(countryIDs: ["CR", "US"], now: now)
        let partial = try await client.fetchHolidayLoadResult(countryIDs: ["CR", "US"], now: now.addingTimeInterval(61), forceRefresh: true)
        XCTAssertEqual(partial.failedCountryIDs, ["US"])
        XCTAssertEqual(partial.events.first { $0.countryID == "US" }?.title, "Original")
        XCTAssertEqual(partial.events.first { $0.countryID == "CR" }?.title, "Updated")
    }

    func testTruncatedCalendarRetainsPreviouslyValidatedHolidays() async throws {
        let log = IntegrationRequestLog()
        let client = GoogleHolidayFeedClient(session: session { request in
            let body = log.record("calls") == 1 ? self.ics("CR") : "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:broken\r\n"
            return self.reply(request, body: body)
        })
        let valid = try await client.fetchHolidayLoadResult(countryIDs: ["CR"], now: now)
        let truncated = try await client.fetchHolidayLoadResult(countryIDs: ["CR"], now: now.addingTimeInterval(61), forceRefresh: true)
        XCTAssertEqual(truncated.failedCountryIDs, ["CR"])
        XCTAssertEqual(truncated.events, valid.events)
    }

    func testInvalid200DoesNotBecomeValidatedHolidayData() async throws {
        let client = GoogleHolidayFeedClient(session: session { request in self.reply(request, body: "not an ICS calendar") })
        let partial = try await client.fetchHolidayLoadResult(countryIDs: ["CR"], now: now)
        XCTAssertFalse(partial.isComplete)
        XCTAssertTrue(partial.availableCountryIDs.isEmpty)
        XCTAssertTrue(partial.events.isEmpty)
    }

    func testMissingCacheRecoversFailedCountryFromLastAppliedRecords() {
        let holiday = GoogleHolidayEvent(id: "shared", title: "Holiday", startDate: now, endDateExclusive: now.addingTimeInterval(86_400),
                                         countryIDs: ["CR", "US"], sourceUIDs: ["shared-source"])
        let record = ManagedGoogleHolidayEventRecord(holiday: holiday, calendarIdentifier: "calendar", eventIdentifier: "event", eventUID: nil)
        let sources = CalendarMonitor.preservingUnavailableHolidaySources([], records: [record], failedCountryIDs: ["US"])
        XCTAssertEqual(sources.map(\.countryID), ["US"])
        XCTAssertEqual(sources.first?.title, holiday.title)
        XCTAssertEqual(sources.first?.startDate, holiday.startDate)
    }

    func testChangedCountryOrDestinationRejectsCapturedHolidayRequest() {
        var captured = AppSettings.defaults
        captured.googleHolidayCountryIDs = ["CR"]
        captured.googleHolidayTargetCalendarID = "old-calendar"
        var latest = captured
        XCTAssertTrue(CalendarMonitor.googleHolidayRequestMatchesSettings(captured, current: latest))
        latest.googleHolidayCountryIDs = ["US"]
        XCTAssertFalse(CalendarMonitor.googleHolidayRequestMatchesSettings(captured, current: latest))
        latest = captured
        latest.googleHolidayTargetCalendarID = "new-calendar"
        XCTAssertFalse(CalendarMonitor.googleHolidayRequestMatchesSettings(captured, current: latest))
    }

    func testFailedRefreshRetriesDespiteRecentWeeklySuccess() {
        XCTAssertTrue(GoogleHolidayRefreshPolicy.isDue(lastRefreshDate: now, lastAttemptDate: now.addingTimeInterval(-60), now: now, lastAttemptFailed: true))
        XCTAssertFalse(GoogleHolidayRefreshPolicy.isDue(lastRefreshDate: now, lastAttemptDate: now.addingTimeInterval(-59), now: now, lastAttemptFailed: true))
    }

    private func ics(_ country: String, title: String = "Holiday") -> String {
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20270101\r\nDTEND;VALUE=DATE:20270102\r\nUID:\(country)-holiday\r\nSUMMARY:\(title)\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    }
}
