import Foundation
import XCTest
@testable import AlertCalendar

final class GameSaleCalendarRulesTests: XCTestCase {
    func testGameSalesRefreshPolicyEvaluatesEveryFifteenMinutesWhileFeedsCacheForSixHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(GameSalesFeedClient.monitorEvaluationInterval, 900)
        XCTAssertEqual(GameSalesFeedClient.refreshInterval, 21_600)
        XCTAssertEqual(GameSalesFeedClient.failedRefreshRetryInterval, 900)
        XCTAssertTrue(
            CalendarMonitor.shouldRefreshGameSales(
                lastAttemptDate: nil,
                now: now,
                forceRefresh: false
            )
        )
        XCTAssertFalse(
            CalendarMonitor.shouldRefreshGameSales(
                lastAttemptDate: now.addingTimeInterval(-899),
                now: now,
                forceRefresh: false
            )
        )
        XCTAssertTrue(
            CalendarMonitor.shouldRefreshGameSales(
                lastAttemptDate: now.addingTimeInterval(-900),
                now: now,
                forceRefresh: false
            )
        )
        XCTAssertFalse(
            CalendarMonitor.shouldRefreshGameSales(
                lastAttemptDate: now.addingTimeInterval(-899),
                lastAttemptFailed: true,
                now: now,
                forceRefresh: false
            )
        )
        XCTAssertTrue(
            CalendarMonitor.shouldRefreshGameSales(
                lastAttemptDate: now.addingTimeInterval(-900),
                lastAttemptFailed: true,
                now: now,
                forceRefresh: false
            )
        )
    }

    func testExternalCleanupRequiresDedicatedGameSalesCalendarName() {
        XCTAssertTrue(CalendarMonitor.isDedicatedGameSalesCalendarTitle("Game Sales"))
        XCTAssertTrue(CalendarMonitor.isDedicatedGameSalesCalendarTitle("game sales"))
        XCTAssertFalse(CalendarMonitor.isDedicatedGameSalesCalendarTitle("Personal"))
        XCTAssertFalse(CalendarMonitor.isDedicatedGameSalesCalendarTitle("Games"))
    }

    func testSemanticMatchIgnoresSourceIdentityTitleCaseAndDiacritics() {
        let calendar = makeCalendar()
        let first = makeSale(
            sourceID: "calendar-existing",
            title: "STEAM Fête de Stratégie",
            officialURL: "https://store.steampowered.com/sale/strategy"
        )
        let second = makeSale(
            sourceID: "feed-upcoming-events",
            title: "fete de strategie",
            officialURL: "https://partner.steamgames.com/doc/marketing/upcoming_events"
        )

        XCTAssertTrue(
            CalendarMonitor.gameSalesSemanticallyMatch(
                first,
                second,
                calendar: calendar
            )
        )
    }

    func testSemanticMatchRejectsDifferentStartEndOrStore() {
        let calendar = makeCalendar()
        let reference = makeSale()
        let differentStart = makeSale(
            startDate: date(year: 2026, month: 6, day: 26),
            endDateExclusive: reference.endDateExclusive
        )
        let differentEnd = makeSale(
            startDate: reference.startDate,
            endDateExclusive: date(year: 2026, month: 7, day: 11)
        )
        let differentStore = makeSale(
            store: .xbox,
            title: "Xbox Summer Sale",
            officialURL: "https://www.xbox.com/promotions/summer-sale"
        )

        XCTAssertFalse(CalendarMonitor.gameSalesSemanticallyMatch(reference, differentStart, calendar: calendar))
        XCTAssertFalse(CalendarMonitor.gameSalesSemanticallyMatch(reference, differentEnd, calendar: calendar))
        XCTAssertFalse(CalendarMonitor.gameSalesSemanticallyMatch(reference, differentStore, calendar: calendar))
    }

    func testCalendarAssociationSurvivesChangedEndDateAndSourceIdentity() {
        let calendar = makeCalendar()
        let reference = makeSale()
        let calendarVersion = makeSale(
            sourceID: "calendar-reindexed-event",
            title: "SUMMER SALE",
            startDate: reference.startDate,
            endDateExclusive: date(year: 2026, month: 7, day: 11),
            officialURL: "https://store.steampowered.com/sale/summer"
        )

        XCTAssertFalse(
            CalendarMonitor.gameSalesSemanticallyMatch(
                reference,
                calendarVersion,
                calendar: calendar
            )
        )
        XCTAssertTrue(
            CalendarMonitor.gameSalesCalendarAssociationMatches(
                reference,
                calendarVersion,
                calendar: calendar
            )
        )
    }

    func testCalendarAssociationRejectsAnotherCampaignOccurrenceOrStore() {
        let calendar = makeCalendar()
        let reference = makeSale()
        let anotherOccurrence = makeSale(
            sourceID: "seasonal-summer-2027",
            startDate: date(year: 2027, month: 6, day: 25),
            endDateExclusive: date(year: 2027, month: 7, day: 10)
        )
        let anotherCampaign = makeSale(
            sourceID: "next-fest-2026",
            title: "Steam Next Fest"
        )
        let anotherStore = makeSale(
            store: .xbox,
            title: "Xbox Summer Sale",
            officialURL: "https://www.xbox.com/promotions/summer-sale"
        )

        XCTAssertFalse(
            CalendarMonitor.gameSalesCalendarAssociationMatches(
                reference,
                anotherOccurrence,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            CalendarMonitor.gameSalesCalendarAssociationMatches(
                reference,
                anotherCampaign,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            CalendarMonitor.gameSalesCalendarAssociationMatches(
                reference,
                anotherStore,
                calendar: calendar
            )
        )
    }

    func testNormalizedTitleRemovesStorePrefixPunctuationCaseAndDiacritics() {
        XCTAssertEqual(
            CalendarMonitor.normalizedGameSaleTitle(
                "  StEaM — Fête de l'Été!  ",
                store: .steam
            ),
            "fete de l ete"
        )
        XCTAssertEqual(
            CalendarMonitor.normalizedGameSaleTitle(
                "MICROSOFT STORE: Súper Saver Sale",
                store: .xbox
            ),
            "super saver sale"
        )
    }

    func testExclusiveEndDateKeepsMidnightAndAdvancesInclusiveLastSecond() {
        let calendar = makeCalendar()
        let exclusiveMidnight = date(year: 2026, month: 7, day: 10)
        let inclusiveLastSecond = date(
            year: 2026,
            month: 7,
            day: 9,
            hour: 23,
            minute: 59,
            second: 59
        )

        XCTAssertEqual(
            CalendarMonitor.gameSaleExclusiveEndDate(
                exclusiveMidnight,
                calendar: calendar
            ),
            exclusiveMidnight
        )
        XCTAssertEqual(
            CalendarMonitor.gameSaleExclusiveEndDate(
                inclusiveLastSecond,
                calendar: calendar
            ),
            exclusiveMidnight
        )
    }

    func testScheduledSalesExcludeSaleWhenNowEqualsExclusiveEnd() {
        let calendar = makeCalendar()
        let endDateExclusive = date(year: 2026, month: 7, day: 10)
        let html = """
        <h2><a name="summer_sale">Steam Summer Sale | June 25 - July 9, 2026</a></h2>
        """

        XCTAssertEqual(
            GameSalesFeedClient.parseScheduledSales(
                fromHTML: html,
                now: endDateExclusive.addingTimeInterval(-1),
                calendar: calendar
            ).count,
            1
        )
        XCTAssertTrue(
            GameSalesFeedClient.parseScheduledSales(
                fromHTML: html,
                now: endDateExclusive,
                calendar: calendar
            ).isEmpty
        )
    }

    func testGameStoreUsesOfficialURLHostEvenWhenPathNamesXboxPublisher() throws {
        let xboxPublisherOnSteam = try XCTUnwrap(
            URL(string: "https://store.steampowered.com/publisher/xbox-game-studios")
        )

        XCTAssertEqual(CalendarMonitor.gameStore(for: xboxPublisherOnSteam), .steam)
        XCTAssertEqual(
            CalendarMonitor.gameStore(
                for: try XCTUnwrap(URL(string: "https://www.xbox.com/promotions/sales"))
            ),
            .xbox
        )
        XCTAssertEqual(
            CalendarMonitor.gameStore(
                for: try XCTUnwrap(URL(string: "https://store.playstation.com/category/deals"))
            ),
            .playStation
        )
        XCTAssertEqual(
            CalendarMonitor.gameStore(
                for: try XCTUnwrap(URL(string: "https://www.nintendo.com/store/sales-and-deals"))
            ),
            .nintendoSwitch
        )
        XCTAssertNil(
            CalendarMonitor.gameStore(
                for: try XCTUnwrap(URL(string: "https://example.com/sale"))
            )
        )
    }

    func testCalendarAlertOptionsExposeStableTitlesAndOffsets() {
        XCTAssertEqual(
            GameSaleCalendarAlertOption.allCases.map(\.rawValue),
            [
                "none",
                "atTimeOfEvent",
                "fifteenMinutesBefore",
                "oneHourBefore",
                "oneDayBefore",
            ]
        )
        XCTAssertEqual(GameSaleCalendarAlertOption.none.title, "None")
        XCTAssertNil(GameSaleCalendarAlertOption.none.relativeOffset())
        XCTAssertEqual(GameSaleCalendarAlertOption.atTimeOfEvent.relativeOffset(), 0)
        XCTAssertEqual(GameSaleCalendarAlertOption.fifteenMinutesBefore.title, "15 minutes before")
        XCTAssertEqual(GameSaleCalendarAlertOption.fifteenMinutesBefore.relativeOffset(), -15 * 60)
        XCTAssertEqual(GameSaleCalendarAlertOption.oneHourBefore.relativeOffset(), -60 * 60)
        XCTAssertEqual(GameSaleCalendarAlertOption.oneDayBefore.relativeOffset(), -24 * 60 * 60)
    }

    func testAutoAddNotificationUsesInclusiveDateRangeAndStableKey() {
        let calendar = makeCalendar()
        let sale = makeSale()
        let inclusiveEnd = date(year: 2026, month: 7, day: 9)
        let formatter = DateIntervalFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.calendar = calendar
        let expectedRange = formatter.string(from: sale.startDate, to: inclusiveEnd)

        let message = CalendarMonitor.gameSaleAutoAddNotificationMessage(
            for: sale,
            calendar: calendar
        )

        XCTAssertEqual(message.title, "Game sale added to Calendar")
        XCTAssertEqual(message.body, "Steam: Steam Summer Sale, \(expectedRange).")
        XCTAssertEqual(
            CalendarMonitor.gameSaleAutoAddNotificationKey(for: sale),
            "gameSale.autoAdd.steam:seasonal-summer-2026"
        )
    }

    func testAutoAddBatchNotificationSummarizesWithoutFlooding() throws {
        let sales = (1...5).map { index in
            makeSale(sourceID: "sale-\(index)", title: "Sale \(index)")
        }
        let message = try XCTUnwrap(
            CalendarMonitor.gameSaleAutoAddBatchNotificationMessage(for: sales)
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(message.title, "5 game sales added to Calendar")
        XCTAssertEqual(message.body, "Sale 1, Sale 2, Sale 3 and 2 more.")
        XCTAssertEqual(
            CalendarMonitor.gameSaleAutoAddBatchNotificationKey(now: now),
            "gameSale.autoAdd.batch.1800000000"
        )
        XCTAssertNil(CalendarMonitor.gameSaleAutoAddBatchNotificationMessage(for: [sales[0]]))
    }

    func testManagedRecordCodableRoundTripPreservesSaleAndCalendarIdentity() throws {
        let record = ManagedGameSaleEventRecord(
            sale: makeSale(),
            calendarIdentifier: "game-sales-calendar",
            eventIdentifier: "event-identifier",
            eventUID: "event-uid"
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(
            ManagedGameSaleEventRecord.self,
            from: data
        )

        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.saleID, "steam:seasonal-summer-2026")
        XCTAssertTrue(decoded.sale.isAllDay)
    }

    func testManagedRecordCodableRoundTripPreservesMissingEventIdentifiers() throws {
        let record = ManagedGameSaleEventRecord(
            sale: makeSale(),
            calendarIdentifier: "game-sales-calendar",
            eventIdentifier: nil,
            eventUID: nil
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(
            ManagedGameSaleEventRecord.self,
            from: data
        )

        XCTAssertEqual(decoded, record)
        XCTAssertNil(decoded.eventIdentifier)
        XCTAssertNil(decoded.eventUID)
    }

    func testGameSaleDefaultsKeepEveryStoreAutomationOffAndEnableEndedEventCleanup() throws {
        let suiteName = "GameSaleCalendarRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppSettingsStore(defaults: defaults).registerDefaults()

        XCTAssertEqual(
            defaults.string(forKey: DefaultsKeys.gameSaleCalendarAlertOption),
            GameSaleCalendarAlertOption.fifteenMinutesBefore.rawValue
        )
        XCTAssertEqual(
            defaults.stringArray(forKey: DefaultsKeys.gameSaleAutoAddStoreIDs),
            []
        )
        XCTAssertTrue(defaults.bool(forKey: DefaultsKeys.enableGameSaleAutoAddNotifications))
        XCTAssertTrue(defaults.bool(forKey: DefaultsKeys.removeEndedGameSalesAutomatically))
        XCTAssertEqual(defaults.stringArray(forKey: DefaultsKeys.dismissedGameSaleEventIDs), [])
    }

    private func makeSale(
        store: GameStore = .steam,
        sourceID: String = "seasonal-summer-2026",
        title: String = "Steam Summer Sale",
        startDate: Date? = nil,
        endDateExclusive: Date? = nil,
        officialURL: String = "https://partner.steamgames.com/doc/marketing/upcoming_events"
    ) -> GameSaleEvent {
        GameSaleEvent(
            store: store,
            sourceID: sourceID,
            title: title,
            startDate: startDate ?? date(year: 2026, month: 6, day: 25),
            endDateExclusive: endDateExclusive ?? date(year: 2026, month: 7, day: 10),
            officialURL: URL(string: officialURL)!
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        makeCalendar().date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }
}
