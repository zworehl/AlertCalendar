import Foundation
import XCTest
@testable import AlertCalendar

final class LocalizationTests: AlertCalendarModelTestCase {
    func testLatinAmericanSpanishUsesTheRegionalIdentifier() {
        XCTAssertEqual(AppLanguage.spanishLatinAmerica.rawValue, "es-419")
        XCTAssertEqual(AppLanguage.spanishLatinAmerica.nativeName, "Español (Latinoamérica)")
        XCTAssertEqual(AppLanguage.spanishLatinAmerica.locale.language.region?.identifier, "419")
    }

    func testLocalizedResourcesAndUnknownKeyFallback() {
        XCTAssertEqual(L10n.lookup("Apply", language: .spanishLatinAmerica), "Aplicar")
        XCTAssertEqual(L10n.lookup("Settings", language: .spanishLatinAmerica), "Configuración")
        XCTAssertEqual(L10n.lookup("Apply", language: .english), "Apply")
        XCTAssertEqual(L10n.lookup("Imported event title", language: .spanishLatinAmerica), "Imported event title")
    }

    func testInterpolationPreservesAccentsEmojiAndPercentSigns() {
        let title = "Revisión de José 🎵 100% %@"
        XCTAssertEqual(
            L10n.text("Skip \(title)", language: .spanishLatinAmerica),
            "Omitir Revisión de José 🎵 100% %@"
        )
        XCTAssertEqual(
            L10n.text("Version \(1.1) (\(2))", language: .spanishLatinAmerica),
            "Versión 1.1 (2)"
        )
    }

    func testMissingLanguagePreferenceKeepsEnglishAndUnsupportedValuesFallBack() throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()
        XCTAssertEqual(store.load().language, .english)
        defaults.set("es-ES", forKey: DefaultsKeys.language)
        XCTAssertEqual(store.load().language, .english)
    }

    func testLanguageRoundTripAndSystemDialogPreference() throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()
        var settings = store.load()
        settings.language = .spanishLatinAmerica
        store.save(settings)
        XCTAssertEqual(store.load().language, .spanishLatinAmerica)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["es-419"])
        settings.language = .english
        store.save(settings)
        XCTAssertEqual(store.load().language, .english)
    }

    func testLanguageParticipatesInApplyAndRevertWithoutChangingLiveStateBeforeApply() {
        let stored = AppSettings.defaults
        var draft = SettingsDraft(settings: stored)
        draft.language = .spanishLatinAmerica
        XCTAssertNotEqual(draft, SettingsDraft(settings: stored))
        XCTAssertEqual(stored.language, .english)
        let applied = draft.applied(to: stored, availableEventCalendarIDs: [])
        XCTAssertEqual(applied.language, .spanishLatinAmerica)
        XCTAssertEqual(SettingsDraft(settings: applied).language, .spanishLatinAmerica)
        draft = SettingsDraft(settings: stored)
        XCTAssertEqual(draft.language, .english)
    }

    func testLanguageChangesInvalidateAgendaFingerprints() {
        let english = AgendaSummaryRequest(now: .distantPast, language: .english, upcomingItems: [])
        let spanish = AgendaSummaryRequest(now: .distantPast, language: .spanishLatinAmerica, upcomingItems: [])
        XCTAssertNotEqual(english.generationFingerprint(usesLinkedPagePreviews: false),
                          spanish.generationFingerprint(usesLinkedPagePreviews: false))
    }

    func testSpanishAgendaInstructionsAndFallback() {
        let request = AgendaSummaryRequest(now: .distantPast, language: .spanishLatinAmerica, upcomingItems: [])
        XCTAssertTrue(AppleIntelligenceAgendaSummaryClient.instructions(maximumWords: 60, language: request.language)
            .contains("Respond in Latin American Spanish"))
        XCTAssertEqual(AgendaSummaryFallback.summary(for: request), "Tu agenda incluye 0 elementos en 0 días.")
    }

    func testEmptySpanishAgendaResponse() async throws {
        let client = AppleIntelligenceAgendaSummaryClient(
            availabilityProvider: { .available },
            responder: { _, _ in XCTFail("No model call is needed for an empty agenda"); return .init(summary: "", coveredItemIndexes: []) }
        )
        let request = AgendaSummaryRequest(now: .distantPast, language: .spanishLatinAmerica, upcomingItems: [])
        let summary = try await client.generateSummary(for: request)
        XCTAssertEqual(summary, "No hay nada programado en esta ventana.")
    }

    func testSpanishSummaryPreservesSourceTitleAndUsesRequestedClock() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)))
        let item = makeUpcomingItem(id: "spanish", title: "Revisión de José", startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(7200))
        let request = AgendaSummaryRequest(now: now, language: .spanishLatinAmerica, timeZone: zone, locale: Locale(identifier: "en_GB"), upcomingItems: [item])
        let summary = AgendaSummaryFallback.summary(for: request)
        XCTAssertTrue(summary.contains("Tu agenda incluye 1 elemento en 1 día."))
        XCTAssertTrue(summary.contains("Hoy a las 13:00: Revisión de José."))
        XCTAssertFalse(summary.contains("Today"))
        XCTAssertFalse(summary.contains("PM"))
        let payload = try AppleIntelligenceAgendaSummaryClient.calendarJSONString(for: request)
        XCTAssertTrue(payload.contains("13:00"))
    }

    @MainActor
    func testSwitchingLanguageUpdatesDatesAndKeepsParsingAndIdentifiersStable() throws {
        let previous = AlertCalendarLanguage.current
        defer { AlertCalendarLanguage.current = previous }
        AlertCalendarLanguage.current = .spanishLatinAmerica
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 17, minute: 30)))
        let spanish = AlertCalendarLanguage.dateFormatter(template: "MMM d h:mm a", clockLocale: Locale(identifier: "en_GB"), timeZone: zone)
        XCTAssertTrue(spanish.string(from: date).contains("oct"))
        XCTAssertTrue(spanish.string(from: date).contains("17:30"))
        XCTAssertFalse(spanish.string(from: date).contains("PM"))
        XCTAssertEqual(AlertCalendarRelativeTimeFormatter.calendarDayRelativeText(for: date, relativeTo: date), "hoy")
        XCTAssertEqual(AlertCalendarRelativeTimeFormatter.elapsedAgoText(from: date, to: date.addingTimeInterval(120), simplified: true), "hace 2m")
        XCTAssertEqual(AstronomyMoment(eventTitle: "Amanecer"), .sunrise)
        XCTAssertEqual(AstronomyMoment(eventTitle: "Sunrise"), .sunrise)
        XCTAssertEqual(AstronomyMoment(eventTitle: "Mediodía solar"), .solarNoon)
        XCTAssertEqual(MeetingBrowserRoute.defaultChromeProfileID, "Default")
        XCTAssertEqual(SlackMeetingStatus.defaultText, "In a meeting")
        XCTAssertTrue(FootballDataAPIClient.liveOddsEntryIsUnavailable(["state": "off"]))
        let rss = """
        <rss><channel><item><title>THQ Nordic Publisher Sale</title>
        <link>https://news.xbox.com/en-us/2026/10/01/thq-nordic-sale/</link>
        <guid>https://news.xbox.com/?p=12345</guid>
        <pubDate>Thu, 01 Oct 2026 17:00:00 +0000</pubDate>
        <description>Save in this publisher sale from October 1 through October 3.</description>
        </item></channel></rss>
        """
        let sales = GameSalesEditorialRSSParser.parseEditorialRSS(xml: rss, store: .xbox, now: date, calendar: calendar)
        XCTAssertEqual(sales.count, 1)
        XCTAssertEqual(sales.first?.title, "THQ Nordic Publisher Sale")
        XCTAssertTrue(CalendarMonitor.isDedicatedGameSalesCalendarTitle("Game Sales"))
        XCTAssertTrue(CalendarMonitor.isDedicatedGameSalesCalendarTitle("Ofertas de videojuegos"))
        let rangeEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: date))
        XCTAssertEqual(AlertCalendarDateRangeFormatter.compactAllDayRange(startDay: date, lastInclusiveDay: rangeEnd, calendar: calendar), "1-3 oct")
        AlertCalendarLanguage.current = .english
        XCTAssertEqual(L10n.text("Apply"), "Apply")
        XCTAssertEqual(AlertCalendarRelativeTimeFormatter.calendarDayRelativeText(for: date, relativeTo: date), "today")
    }

    private let defaultsSuiteName = "AlertCalendarTests.Localization.\(UUID().uuidString)"
    private func isolatedDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
    }
}
