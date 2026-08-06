import Foundation
import XCTest
@testable import AlertCalendar

final class GoogleHolidayIntegrationTests: XCTestCase {
    func testCatalogContainsEveryVerifiedGoogleCountryFeed() throws {
        XCTAssertEqual(GoogleHolidayCountry.all.count, 256)
        XCTAssertEqual(Set(GoogleHolidayCountry.all.map(\.id)).count, GoogleHolidayCountry.all.count)
        XCTAssertEqual(GoogleHolidayCountry.byID["CR"]?.googleCalendarSlug, "cr")
        XCTAssertEqual(GoogleHolidayCountry.byID["US"]?.googleCalendarSlug, "usa")
        XCTAssertEqual(GoogleHolidayCountry.byID["ZA"]?.googleCalendarSlug, "sa")
        XCTAssertNil(GoogleHolidayCountry.byID["CQ"])

        for country in GoogleHolidayCountry.all {
            XCTAssertEqual(country.feedURL.scheme, "https")
            XCTAssertEqual(country.feedURL.host, "calendar.google.com")
            XCTAssertTrue(country.feedURL.path.hasSuffix("/public/basic.ics"))
            XCTAssertEqual(country.flag.count, 1)
        }
    }

    func testRefreshPolicyUsesFixedWeeklyCadenceAndDueBoundaries() {
        XCTAssertEqual(GoogleHolidayRefreshPolicy.interval, 604_800)
        XCTAssertEqual(GoogleHolidayRefreshPolicy.failureRetryInterval, 21_600)

        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(
            GoogleHolidayRefreshPolicy.isDue(
                lastRefreshDate: now,
                now: now,
                forceRefresh: true
            )
        )
        XCTAssertTrue(GoogleHolidayRefreshPolicy.isDue(lastRefreshDate: nil, now: now))
        XCTAssertFalse(
            GoogleHolidayRefreshPolicy.isDue(
                lastRefreshDate: now.addingTimeInterval(-604_799),
                now: now
            )
        )
        XCTAssertTrue(
            GoogleHolidayRefreshPolicy.isDue(
                lastRefreshDate: now.addingTimeInterval(-604_800),
                now: now
            )
        )
        XCTAssertFalse(
            GoogleHolidayRefreshPolicy.isDue(
                lastRefreshDate: now.addingTimeInterval(-604_800),
                lastAttemptDate: now.addingTimeInterval(-21_599),
                now: now
            )
        )
        XCTAssertTrue(
            GoogleHolidayRefreshPolicy.isDue(
                lastRefreshDate: now.addingTimeInterval(-604_800),
                lastAttemptDate: now.addingTimeInterval(-21_600),
                now: now
            )
        )
    }

    func testParserReadsGoogleAllDayEventsUnfoldsValuesAndSkipsCancelledEvents() throws {
        let text = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        BEGIN:VEVENT\r
        DTSTART;VALUE=DATE:20261225\r
        DTEND;VALUE=DATE:20261226\r
        UID:christmas-cr@google.com\r
        SUMMARY:Christmas\\, Peace &\r
         Joy\r
        STATUS:CONFIRMED\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        DTSTART;VALUE=DATE:20260101\r
        UID:cancelled@google.com\r
        SUMMARY:Cancelled holiday\r
        STATUS:CANCELLED\r
        END:VEVENT\r
        END:VCALENDAR\r
        """

        let events = try GoogleHolidayICSParser.parse(
            text: text,
            countryID: "CR",
            calendar: testCalendar
        )
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.sourceUID, "christmas-cr@google.com")
        XCTAssertEqual(event.countryID, "CR")
        XCTAssertEqual(event.title, "Christmas, Peace &Joy")
        XCTAssertEqual(dayComponents(event.startDate), DateComponents(year: 2026, month: 12, day: 25))
        XCTAssertEqual(dayComponents(event.endDateExclusive), DateComponents(year: 2026, month: 12, day: 26))
    }

    func testMergerCombinesSameHolidayAndDateWithAllCountryFlags() throws {
        let christmas = try date(2026, 12, 25)
        let nextDay = try date(2026, 12, 26)
        let laterChristmas = try date(2027, 12, 25)
        let laterEnd = try date(2027, 12, 26)
        let merged = GoogleHolidayMerger.merge(
            [
                sourceEvent(uid: "cr", countryID: "CR", title: "Christmas Day", start: christmas, end: nextDay),
                sourceEvent(uid: "co", countryID: "CO", title: "christmas day", start: christmas, end: nextDay),
                sourceEvent(uid: "us", countryID: "US", title: "Christmas Day", start: christmas, end: nextDay),
                sourceEvent(uid: "us-next", countryID: "US", title: "Christmas Day", start: laterChristmas, end: laterEnd),
            ],
            calendar: testCalendar
        )

        XCTAssertEqual(merged.count, 2)
        let first = try XCTUnwrap(merged.first)
        XCTAssertEqual(first.countryIDs, ["CO", "CR", "US"])
        XCTAssertEqual(first.sourceUIDs, ["co", "cr", "us"])
        XCTAssertEqual(first.calendarTitle, "🇨🇴 🇨🇷 🇺🇸 Christmas Day")
    }

    func testMergerRemovesHolidayDecoratorsAndDayOffWrappersOnTheSameDate() throws {
        let start = try date(2026, 10, 12)
        let end = try date(2026, 10, 13)
        let merged = GoogleHolidayMerger.merge(
            [
                sourceEvent(
                    uid: "co",
                    countryID: "CO",
                    title: "Columbus Day Holiday",
                    start: start,
                    end: end
                ),
                sourceEvent(
                    uid: "us",
                    countryID: "US",
                    title: "Columbus Day",
                    start: start,
                    end: end
                ),
                sourceEvent(
                    uid: "hn",
                    countryID: "HN",
                    title: "Columbus Day (regional holiday)",
                    start: start,
                    end: end
                ),
                sourceEvent(
                    uid: "as",
                    countryID: "AS",
                    title: "Day off for Columbus Day",
                    start: start,
                    end: end
                ),
            ],
            calendar: testCalendar
        )

        let holiday = try XCTUnwrap(merged.first)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(holiday.title, "Columbus Day")
        XCTAssertEqual(holiday.countryIDs, ["AS", "CO", "HN", "US"])
        XCTAssertEqual(holiday.sourceUIDs, ["as", "co", "hn", "us"])
    }

    func testMergerKeepsEquivalentTitlesSeparateWhenDatesDiffer() throws {
        let actualStart = try date(2027, 10, 11)
        let observedStart = try date(2027, 10, 18)
        let merged = GoogleHolidayMerger.merge(
            [
                sourceEvent(
                    uid: "us",
                    countryID: "US",
                    title: "Columbus Day",
                    start: actualStart,
                    end: try date(2027, 10, 12)
                ),
                sourceEvent(
                    uid: "co",
                    countryID: "CO",
                    title: "Columbus Day Holiday",
                    start: observedStart,
                    end: try date(2027, 10, 19)
                ),
            ],
            calendar: testCalendar
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.map(\.countryIDs)), Set([["US"], ["CO"]]))
    }

    func testMergerUsesDateScopedWorkersDayAliases() throws {
        let mayDay = try date(2028, 5, 1)
        let mayDayEnd = try date(2028, 5, 2)
        let september = try date(2028, 9, 4)
        let septemberEnd = try date(2028, 9, 5)
        let merged = GoogleHolidayMerger.merge(
            [
                sourceEvent(uid: "labor", countryID: "US", title: "Labor Day", start: mayDay, end: mayDayEnd),
                sourceEvent(uid: "labour", countryID: "GB", title: "Labour Day", start: mayDay, end: mayDayEnd),
                sourceEvent(uid: "may", countryID: "IE", title: "May Day", start: mayDay, end: mayDayEnd),
                sourceEvent(
                    uid: "workers",
                    countryID: "CR",
                    title: "International Workers' Day",
                    start: mayDay,
                    end: mayDayEnd
                ),
                sourceEvent(
                    uid: "labor-september",
                    countryID: "US",
                    title: "Labor Day",
                    start: september,
                    end: septemberEnd
                ),
                sourceEvent(
                    uid: "may-september",
                    countryID: "IE",
                    title: "May Day",
                    start: september,
                    end: septemberEnd
                ),
            ],
            calendar: testCalendar
        )

        XCTAssertEqual(merged.count, 3)
        let workersDay = try XCTUnwrap(merged.first(where: { $0.startDate == mayDay }))
        XCTAssertEqual(workersDay.title, "International Workers' Day")
        XCTAssertEqual(workersDay.countryIDs, ["CR", "GB", "IE", "US"])
        XCTAssertEqual(
            Set(merged.filter { $0.startDate == september }.map(\.title)),
            ["Labor Day", "May Day"]
        )
    }

    func testMergerCombinesExplicitReligiousAndCulturalAliases() throws {
        let christmas = try date(2026, 12, 25)
        let christmasEnd = try date(2026, 12, 26)
        let eid = try date(2027, 3, 10)
        let eidEnd = try date(2027, 3, 11)
        let merged = GoogleHolidayMerger.merge(
            [
                sourceEvent(uid: "christmas", countryID: "US", title: "Christmas", start: christmas, end: christmasEnd),
                sourceEvent(
                    uid: "catholic",
                    countryID: "CO",
                    title: "Catholic Christmas Day",
                    start: christmas,
                    end: christmasEnd
                ),
                sourceEvent(
                    uid: "eid",
                    countryID: "AE",
                    title: "Eid al-Fitr (tentative)",
                    start: eid,
                    end: eidEnd
                ),
                sourceEvent(
                    uid: "ramadan",
                    countryID: "TR",
                    title: "Ramadan Feast Holiday",
                    start: eid,
                    end: eidEnd
                ),
                sourceEvent(uid: "idul", countryID: "ID", title: "Idul Fitri", start: eid, end: eidEnd),
            ],
            calendar: testCalendar
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(
            merged.first(where: { $0.startDate == christmas })?.calendarTitle,
            "🇨🇴 🇺🇸 Christmas Day"
        )
        XCTAssertEqual(
            merged.first(where: { $0.startDate == eid })?.calendarTitle,
            "🇦🇪 🇮🇩 🇹🇷 Eid al-Fitr"
        )
    }

    func testMergerDoesNotCollapseAdjacentDaysOrDifferentCommemorations() throws {
        let start = try date(2026, 10, 12)
        let end = try date(2026, 10, 13)
        let merged = GoogleHolidayMerger.merge(
            [
                sourceEvent(uid: "columbus", countryID: "US", title: "Columbus Day", start: start, end: end),
                sourceEvent(
                    uid: "indigenous",
                    countryID: "CO",
                    title: "Indigenous Resistance Day",
                    start: start,
                    end: end
                ),
                sourceEvent(uid: "eid", countryID: "AE", title: "Eid al-Fitr", start: start, end: end),
                sourceEvent(uid: "eid-eve", countryID: "OM", title: "Eid al-Fitr Eve", start: start, end: end),
                sourceEvent(uid: "eid-2", countryID: "PH", title: "Eid al-Fitr Day 2", start: start, end: end),
                sourceEvent(uid: "christmas", countryID: "CR", title: "Christmas Day", start: start, end: end),
                sourceEvent(uid: "eve", countryID: "GB", title: "Christmas Eve", start: start, end: end),
                sourceEvent(uid: "boxing", countryID: "CA", title: "Boxing Day", start: start, end: end),
            ],
            calendar: testCalendar
        )

        XCTAssertEqual(merged.count, 8)
    }

    func testSemanticKeySupportsLegacyManagedTitlesWithCountryFlags() throws {
        let start = try date(2026, 10, 12)
        XCTAssertEqual(
            GoogleHolidayMerger.semanticKey(
                title: "🇨🇴 Columbus Day Holiday",
                startDate: start,
                calendar: testCalendar
            ),
            GoogleHolidayMerger.semanticKey(
                title: "Columbus Day",
                startDate: start,
                calendar: testCalendar
            )
        )
    }

    func testCalendarEndDateConvertsGoogleExclusiveEndToInclusiveLastSecond() throws {
        let exclusiveEnd = try date(2026, 7, 21)
        let calendarEnd = CalendarMonitor.googleHolidayCalendarEndDate(
            endDateExclusive: exclusiveEnd
        )

        XCTAssertEqual(calendarEnd, exclusiveEnd.addingTimeInterval(-1))
        XCTAssertEqual(
            testCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: calendarEnd),
            DateComponents(year: 2026, month: 7, day: 20, hour: 23, minute: 59, second: 59)
        )
    }

    func testCalendarEndNormalizationAcceptsInclusiveAndExclusiveRepresentations() throws {
        let exclusiveEnd = try date(2026, 7, 21)
        let inclusiveEnd = exclusiveEnd.addingTimeInterval(-1)

        XCTAssertEqual(
            CalendarMonitor.googleHolidayExclusiveEndDate(
                fromCalendarEndDate: exclusiveEnd,
                calendar: testCalendar
            ),
            exclusiveEnd
        )
        XCTAssertEqual(
            CalendarMonitor.googleHolidayExclusiveEndDate(
                fromCalendarEndDate: inclusiveEnd,
                calendar: testCalendar
            ),
            exclusiveEnd
        )
    }

    func testManagedHolidayMarkerMigrationRecognizesV1V2AndV3Notes() {
        XCTAssertTrue(
            CalendarMonitor.isManagedGoogleHolidayNotes(
                "Managed by Alert Calendar • Google Holidays v1\nHoliday key: legacy"
            )
        )
        XCTAssertTrue(
            CalendarMonitor.isManagedGoogleHolidayNotes(
                "Managed by Alert Calendar • Google Holidays v2\nHoliday key: legacy"
            )
        )
        XCTAssertTrue(
            CalendarMonitor.isManagedGoogleHolidayNotes(
                "Managed by Alert Calendar • Google Holidays v3\nHoliday key: current"
            )
        )
        XCTAssertFalse(CalendarMonitor.isManagedGoogleHolidayNotes("Unmanaged holiday"))
    }

    func testSubscribedCalendarDetectionFindsCurrentCountryCalendars() {
        XCTAssertEqual(
            GoogleHolidayCountry.matchingSubscribedCalendarTitles(
                [
                    "Holidays in Costa Rica",
                    "Holidays in Colombia",
                    "Holidays and Observances in United States",
                    "Phases of the moon",
                ]
            ),
            ["CO", "CR", "US"]
        )
    }

    func testHolidaySettingsPersistAndNormalizeCountryIDs() throws {
        let suiteName = "GoogleHolidayIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()

        var settings = store.load()
        settings.googleHolidayCountryIDs = ["cr", "CO", "not-a-country"]
        settings.googleHolidayTargetCalendarID = "holiday-calendar"
        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded.googleHolidayCountryIDs, ["CO", "CR"])
        XCTAssertEqual(loaded.googleHolidayTargetCalendarID, "holiday-calendar")
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(testCalendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private func dayComponents(_ date: Date) -> DateComponents {
        testCalendar.dateComponents([.year, .month, .day], from: date)
    }

    private func sourceEvent(
        uid: String,
        countryID: String,
        title: String,
        start: Date,
        end: Date
    ) -> GoogleHolidaySourceEvent {
        GoogleHolidaySourceEvent(
            sourceUID: uid,
            countryID: countryID,
            title: title,
            startDate: start,
            endDateExclusive: end
        )
    }
}
