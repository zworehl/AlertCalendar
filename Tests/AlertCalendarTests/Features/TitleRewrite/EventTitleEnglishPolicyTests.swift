import XCTest
@testable import AlertCalendar

final class EventTitleEnglishPolicyTests: XCTestCase {
    func testBirthdayProgressivelyAbbreviatesBeforeSacrificingIdentity() {
        let cases: [(Int, String)] = [
            (28, "Sebastián Gutiérrez Birthday"),
            (24, "Sebastián Gutiérrez Bday"),
            (20, "Sebastián G. Bday"),
            (17, "Sebastián G. Bday"),
            (16, "S. G. Bday"),
            (12, "S. G. Bday"),
            (10, "S. G. Bday"),
        ]
        for (limit, expected) in cases {
            let result = EventTitlePresentationResolver.resolve(
                originalTitle: "Sebastián Gutiérrez’s 26th Birthday",
                rewrittenTitle: "Sebastián Gutiérrez 26th", maximumCharacters: limit,
                isEnabled: true, isBirthday: true, usesModelRewrite: false
            )
            XCTAssertEqual(result.title, expected)
            XCTAssertTrue(result.usesResolvedTitle)
            XCTAssertLessThanOrEqual(result.title.count, limit)
        }
    }

    func testBirthdayRecognizesOnlyCompleteEnglishNamesAndCelebrations() {
        for title in ["Buy a birthday gift for Ana", "Plan Alex's birthday party", "Birthday planning", "Prepare for Ana's Birthday", "Ana cumpleaños", "26th Annual Review"] {
            XCTAssertNil(EventBirthdayTitle.parse(title), title)
        }
        XCTAssertEqual(EventBirthdayTitle.parse("Ana’s Birthday")?.name, "Ana")
        XCTAssertEqual(EventBirthdayTitle.parse("Ana's 21st birthday")?.name, "Ana")
        XCTAssertEqual(EventBirthdayTitle.parse("Mary-Jane O’Connor Birthday")?.name, "Mary-Jane O’Connor")
        XCTAssertEqual(EventBirthdayTitle.parse("Ana", knownBirthday: true)?.name, "Ana")
        XCTAssertNil(EventBirthdayTitle.parse("Ana"))
    }

    func testBirthdayInitialCollisionUsesOriginalForVisualFallback() {
        let source = "Sebastián Gutiérrez’s 26th Birthday"
        let result = EventTitlePresentationResolver.resolve(
            originalTitle: source, rewrittenTitle: nil, maximumCharacters: 10,
            isEnabled: true, isBirthday: true, otherBirthdayNames: ["Sofía García"]
        )
        XCTAssertEqual(result.title, source)
        XCTAssertFalse(result.usesResolvedTitle)
    }

    func testModelAndLocalCompactorPreserveEssentialDistinctions() {
        let cases: [(String, String, String)] = [
            ("Buy a birthday gift for Ana", "Ana Birthday", "Buy Ana birthday gift"),
            ("Plan Alex's retirement party", "Alex retirement party", "Plan Alex retirement party"),
            ("Driving test preparation", "Driving test", "Driving test Prep"),
            ("Cancel dentist appointment", "Canceled dentist Appt", "Cancel dentist Appt"),
            ("Canceled dentist appointment", "Cancel dentist Appt", "Cancelled dentist Appt"),
            ("Dentist appointment not confirmed", "Dentist Appt confirmed", "Dentist Appt not confirmed"),
            ("Mandatory safety training", "Optional safety training", "Mandatory training"),
            ("Rent payment overdue", "Rent payment", "Rent payment overdue"),
            ("Passport renewal deadline", "Passport renewal", "Passport renewal deadline"),
            ("Pick up Alex", "Drop off Alex", "Pick up Alex"),
            ("Pick up Alex", "Pick up Sam", "Pick up Alex"),
            ("Buy a birthday gift for Ana", "Buy Mia birthday gift", "Buy Ana birthday gift"),
            ("Flight AA123 SJO–MIA", "Flight AA123 MIA–SJO", "Flight AA123 SJO–MIA"),
            ("Project review Phase 2", "Project review", "Project review Phase 2"),
            ("GeoGuessr Championship Semifinals", "GeoGuessr Finals", "GeoGuessr Semifinals"),
            ("Christmas Eve", "Christmas Day", "Christmas Eve"),
            ("Dentist follow-up appointment", "Dentist initial Appt", "Dentist follow-up Appt"),
            ("Review Friday's release", "Review release", "Review Friday's release"),
            ("Release v2.14.0 rollout blocked", "Release v2.14 rollout blocked", "Release v2.14.0 blocked"),
        ]
        for (source, bad, good) in cases {
            let request = EventTitleRewriteRequest(title: source, maximumCharacters: 40)
            XCTAssertNil(AppleIntelligenceEventTitleRewriter.acceptedTitle(bad, for: request), source)
            XCTAssertNotNil(AppleIntelligenceEventTitleRewriter.acceptedTitle(good, for: request), good)
            for limit in [10, 12, 16, 20, 24, 28] {
                let compact = EventTitleSemanticCompactor.compact(title: source, maximumCharacters: limit)
                if compact != source {
                    XCTAssertLessThanOrEqual(compact.count, limit, source)
                    XCTAssertNotNil(AppleIntelligenceEventTitleRewriter.acceptedTitle(
                        compact, for: EventTitleRewriteRequest(title: source, maximumCharacters: limit)
                    ), "\(source) -> \(compact)")
                }
            }
        }
    }

    func testApprovedAbbreviationsWorkWithoutAppleIntelligence() {
        let result = EventTitlePresentationResolver.resolve(
            originalTitle: "Dentist appointment", rewrittenTitle: "Unrelated event",
            maximumCharacters: 12, isEnabled: true, isBirthday: false, usesModelRewrite: false
        )
        XCTAssertEqual(result.title, "Dentist Appt")
        XCTAssertTrue(result.usesResolvedTitle)
    }

    func testEnglishOnlyVocabularyPreservesUnicodeNames() {
        XCTAssertFalse(EventTitleIntentGuard.isCoreIntent("examen"))
        XCTAssertFalse(EventTitleSemanticSignals.isMeaningChanging("cancelado"))
        XCTAssertFalse(EventTitleSemanticSignals.isMeaningChanging("annulé"))
        XCTAssertTrue(EventTitleIntentGuard.isCoreIntent("Prep"))
        XCTAssertNotNil(AppleIntelligenceEventTitleRewriter.acceptedTitle(
            "Ratón's license test", for: EventTitleRewriteRequest(title: "Ratón's driving license test", maximumCharacters: 24)
        ))
    }

    func testDropdownPreferencePersistsWithoutModelAndAtSmallLimits() throws {
        let suite = "EventTitleEnglishPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        var settings = AppSettings.defaults
        settings.useEventTitleEllipsis = true
        settings.rewriteEventTitlesWithAppleIntelligence = false
        settings.useRewrittenEventTitlesInDropdown = true
        settings.eventTitleMaxCharacters = 8
        store.save(settings)
        let loaded = store.load()
        XCTAssertTrue(loaded.useRewrittenEventTitlesInDropdown)
        XCTAssertFalse(loaded.rewriteEventTitlesWithAppleIntelligence)
        var draft = SettingsDraft(settings: loaded)
        draft.useRewrittenEventTitlesInDropdown = false
        XCTAssertFalse(draft.applied(to: loaded, availableEventCalendarIDs: []).useRewrittenEventTitlesInDropdown)
    }

    func testAnniversaryOmitsOrdinalButKeepsPeopleAndKind() {
        let original = "Ana and Luis’s 10th Wedding Anniversary"
        let compact = EventTitleSemanticCompactor.compact(title: original, maximumCharacters: 24)
        XCTAssertEqual(compact, "Ana & Luis Wedding Anniv")
        XCTAssertNil(AppleIntelligenceEventTitleRewriter.acceptedTitle(
            "Ana Wedding Anniv", for: EventTitleRewriteRequest(title: original, maximumCharacters: 24)
        ))
        XCTAssertNil(EventAnniversaryTitle.parse("Plan Ana's wedding anniversary"))
    }

    func testUnsupportedProseKeepsSourceForVisualTruncation() {
        let source = "Reunión trimestral de producto y operaciones"
        XCTAssertEqual(EventTitleSemanticCompactor.compact(title: source, maximumCharacters: 16), source)
    }

    func testEnglishDatesKeepClockPreferenceAndCountryNames() throws {
        let date = Date(timeIntervalSince1970: 0)
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let formatter = AlertCalendarLanguage.dateFormatter(template: "MMM d h:mm a", clockLocale: Locale(identifier: "es_CR"), timeZone: zone)
        XCTAssertTrue(formatter.string(from: date).contains("Jan"))
        XCTAssertEqual(GoogleHolidayCountry.byID["DE"]?.displayName, "Germany")
        XCTAssertTrue(AlertCalendarLanguage.uses24HourTime(Locale(identifier: "en_GB")))
        XCTAssertFalse(AlertCalendarLanguage.uses24HourTime(Locale(identifier: "en_US")))
    }
}
