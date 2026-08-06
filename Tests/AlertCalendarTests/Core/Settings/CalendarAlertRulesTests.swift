import EventKit
import Foundation
import XCTest
@testable import AlertCalendar

final class CalendarAlertRulesTests: XCTestCase {
    func testRulesAreNormalizedPerCalendarAndDeduplicateAlerts() throws {
        let firstAlert = CalendarEventAlert(relativeOffsetSeconds: -15 * 60)
        let duplicateAlert = CalendarEventAlert(relativeOffsetSeconds: -15 * 60)
        let firstRule = CalendarAlertRule(
            calendarID: " work ",
            timedEventAlerts: [firstAlert, duplicateAlert]
        )
        let duplicateRule = CalendarAlertRule(calendarID: "work", scope: .allEvents)
        let missingRule = CalendarAlertRule(calendarID: "missing")

        let normalized = CalendarAlertRule.normalized(
            [firstRule, duplicateRule, missingRule],
            validCalendarIDs: ["work"]
        )

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized.first?.calendarID, "work")
        XCTAssertEqual(normalized.first?.scope, .invitationsOnly)
        XCTAssertEqual(normalized.first?.timedEventAlerts.count, 1)
    }

    func testRuleNormalizationDoesNotImposeAnAlertCountLimit() throws {
        let alerts = (1 ... 25).map { index in
            CalendarEventAlert(relativeOffsetSeconds: -index * 60)
        }
        let rule = try XCTUnwrap(
            CalendarAlertRule(
                calendarID: "work",
                timedEventAlerts: alerts
            ).normalized
        )

        XCTAssertEqual(rule.timedEventAlerts.count, alerts.count)
    }

    func testDefaultAlertsReceiveUniqueStableRowIDs() {
        let firstRule = CalendarAlertRule(calendarID: "work")
        let secondRule = CalendarAlertRule(calendarID: "personal")

        XCTAssertNotEqual(
            firstRule.timedEventAlerts.first?.id,
            secondRule.timedEventAlerts.first?.id
        )
        XCTAssertNotEqual(
            firstRule.allDayEventAlerts.first?.id,
            secondRule.allDayEventAlerts.first?.id
        )
    }

    func testAlertNormalizationClampsOffset() {
        let alert = CalendarEventAlert(relativeOffsetSeconds: Int.max).normalized

        XCTAssertEqual(
            alert.relativeOffsetSeconds,
            CalendarEventAlert.maximumAbsoluteOffsetSeconds
        )
    }

    func testStorePersistsStructuredPerCalendarRules() throws {
        let suiteName = "CalendarAlertRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()
        var settings = store.load()
        settings.calendarAlertRules = [
            CalendarAlertRule(
                calendarID: "work",
                scope: .allEvents,
                overwriteExistingAlerts: true,
                timedEventAlerts: [
                    CalendarEventAlert(relativeOffsetSeconds: -30 * 60),
                    CalendarEventAlert(relativeOffsetSeconds: -24 * 60 * 60),
                ],
                allDayEventAlerts: []
            ),
        ]

        store.save(settings)

        let loadedRule = try XCTUnwrap(store.load().calendarAlertRules.first)
        XCTAssertEqual(loadedRule.calendarID, "work")
        XCTAssertEqual(loadedRule.scope, .allEvents)
        XCTAssertTrue(loadedRule.overwriteExistingAlerts)
        XCTAssertEqual(loadedRule.timedEventAlerts.count, 2)
        XCTAssertEqual(loadedRule.timedEventAlerts.first?.relativeOffsetSeconds, -30 * 60)
        XCTAssertEqual(loadedRule.timedEventAlerts.last?.relativeOffsetSeconds, -24 * 60 * 60)
        XCTAssertTrue(loadedRule.allDayEventAlerts.isEmpty)
    }

    func testLegacyDeliveryFieldsAreIgnoredWhenLoadingRules() throws {
        let data = try XCTUnwrap(
            """
            [{
              "calendarID": "work",
              "isEnabled": true,
              "scope": "invitationsOnly",
              "overwriteExistingAlerts": true,
              "timedEventAlerts": [{
                "id": "00000000-0000-0000-0000-000000000001",
                "timingKind": "relative",
                "relativeOffsetSeconds": -900,
                "delivery": "email",
                "soundName": "Glass",
                "emailAddress": "person@example.com"
              }],
              "allDayEventAlerts": []
            }]
            """.data(using: .utf8)
        )

        let rules = try JSONDecoder().decode([CalendarAlertRule].self, from: data)

        XCTAssertEqual(rules.first?.timedEventAlerts.first?.relativeOffsetSeconds, -900)
    }

    func testAdditiveResolutionPreservesExistingAndAddsOnlyMissingAlarms() {
        let existing = EKAlarm(relativeOffset: -5 * 60)
        let duplicate = EKAlarm(relativeOffset: -5 * 60)
        let desired = EKAlarm(relativeOffset: -30 * 60)

        let resolved = CalendarMonitor.resolvedCalendarAlarms(
            existing: [existing],
            desired: [duplicate, desired],
            overwriteExisting: false
        )

        XCTAssertEqual(resolved.count, 2)
        XCTAssertTrue(CalendarMonitor.calendarAlarmsAreEquivalent(resolved, [existing, desired]))
    }

    func testOverwriteResolutionUsesExactDesiredSeries() {
        let existing = EKAlarm(relativeOffset: -5 * 60)
        let firstDesired = EKAlarm(relativeOffset: -15 * 60)
        let secondDesired = EKAlarm(relativeOffset: -60 * 60)

        let resolved = CalendarMonitor.resolvedCalendarAlarms(
            existing: [existing],
            desired: [firstDesired, secondDesired],
            overwriteExisting: true
        )

        XCTAssertTrue(
            CalendarMonitor.calendarAlarmsAreEquivalent(
                resolved,
                [firstDesired, secondDesired]
            )
        )
    }

    func testResolutionDoesNotImposeAProviderSpecificAlertLimit() {
        let desired = (1 ... 25).map {
            EKAlarm(relativeOffset: TimeInterval(-$0 * 60))
        }

        let resolved = CalendarMonitor.resolvedCalendarAlarms(
            existing: [],
            desired: desired,
            overwriteExisting: true
        )

        XCTAssertEqual(resolved.count, desired.count)
        XCTAssertTrue(CalendarMonitor.calendarAlarmsAreEquivalent(resolved, desired))
    }

    func testResolutionHonorsExplicitProviderAlertLimit() {
        let desired = [
            EKAlarm(relativeOffset: -5 * 60),
            EKAlarm(relativeOffset: -30 * 60),
        ]

        let resolved = CalendarMonitor.resolvedCalendarAlarms(
            existing: [],
            desired: desired,
            overwriteExisting: true,
            maximumAlarmCount: 1
        )

        XCTAssertEqual(resolved.count, 1)
        XCTAssertTrue(CalendarMonitor.calendarAlarmsAreEquivalent(resolved, [desired[0]]))
    }

    func testSyncHorizonIncludesLongestLeadAndBuffer() {
        let now = Date(timeIntervalSince1970: 1_000)
        let rule = CalendarAlertRule(
            calendarID: "work",
            timedEventAlerts: [
                CalendarEventAlert(relativeOffsetSeconds: -14 * 24 * 60 * 60),
            ]
        )

        let endDate = CalendarMonitor.calendarAlertRuleSyncEndDate(
            now: now,
            rules: [rule],
            lookAheadHours: 24
        )

        XCTAssertEqual(
            endDate.timeIntervalSince(now),
            21 * 24 * 60 * 60,
            accuracy: 1
        )
    }

    func testCompleteScanWindowsCoverEntireRangeInFourYearBlocks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 1998, month: 3, day: 12))
        )
        let end = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2010, month: 8, day: 20))
        )

        let windows = CalendarMonitor.completeCalendarAlertRuleScanWindows(
            start: start,
            end: end
        )

        XCTAssertEqual(windows.first?.start, start)
        XCTAssertEqual(windows.last?.end, end)
        XCTAssertEqual(windows.count, 4)
        for (current, next) in zip(windows, windows.dropFirst()) {
            XCTAssertEqual(current.end, next.start)
        }
        for window in windows {
            let maximumEnd = try XCTUnwrap(
                calendar.date(byAdding: .year, value: 4, to: window.start)
            )
            XCTAssertLessThanOrEqual(window.end, maximumEnd)
        }
    }

    func testCompleteSyncFingerprintIsOrderIndependentAndTracksRuleChanges() throws {
        let work = CalendarAlertRule(calendarID: "work")
        var personal = CalendarAlertRule(calendarID: "personal")
        let first = try XCTUnwrap(
            CalendarMonitor.calendarAlertRuleFingerprint([work, personal])
        )
        let reordered = try XCTUnwrap(
            CalendarMonitor.calendarAlertRuleFingerprint([personal, work])
        )

        personal.timedEventAlerts[0].relativeOffsetSeconds = -30 * 60
        let changed = try XCTUnwrap(
            CalendarMonitor.calendarAlertRuleFingerprint([work, personal])
        )

        XCTAssertEqual(first, reordered)
        XCTAssertNotEqual(first, changed)
    }

    func testRecurringAlertMutationNeverUsesFutureEventsSpan() {
        let event = EKEvent(eventStore: EKEventStore())
        event.recurrenceRules = [
            EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: 1,
                end: nil
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.calendarAlertMutationSpan(for: event).rawValue,
            EKSpan.thisEvent.rawValue
        )
    }

    func testAllDayDescriptionsMatchAppleStylePresets() {
        XCTAssertEqual(
            CalendarEventAlert(relativeOffsetSeconds: 9 * 60 * 60)
                .timingDescription(isAllDay: true),
            "On day of event (9:00 AM)"
        )
        XCTAssertEqual(
            CalendarEventAlert(relativeOffsetSeconds: -15 * 60 * 60)
                .timingDescription(isAllDay: true),
            "1 day before (9:00 AM)"
        )
    }
}
