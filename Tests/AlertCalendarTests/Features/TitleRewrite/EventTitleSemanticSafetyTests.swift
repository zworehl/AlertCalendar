import XCTest
@testable import AlertCalendar

final class EventTitleSemanticSafetyTests: XCTestCase {
    func testSemanticFallbackPreservesMeaningChangingStatus() {
        let title = EventTitleRewriteResolver.resolvedTitle(
            nil,
            originalTitle: "Project launch review — canceled",
            maximumCharacters: 26
        )

        XCTAssertTrue(title.localizedCaseInsensitiveContains("canceled"), title)
        XCTAssertLessThanOrEqual(title.count, 26)
    }

    func testSemanticFallbackMaintainsSafetyInvariantsAcrossTitleFamilies() {
        let cases: [(title: String, maximumCharacters: Int)] = [
            ("GeoGuessr World Championship — Finals Day", 26),
            ("Submit the annual budget report to Finance", 24),
            ("Connect with Jonn for defect : WHD-15218", 26),
            ("Cancel the dentist appointment — postponed", 28),
            ("PLAN FAMILY DINNER FOR SUNDAY", 18),
            ("Quarterly product and operations review", 24),
            ("Product launch appointment", 24),
            ("Product delivery delayed", 24),
            ("Release v2.14.0 rollout blocked", 24),
            ("Review Project Apollo requirements with Maya", 24),
        ]

        for item in cases {
            let compacted = EventTitleRewriteResolver.semanticallyCompactedTitle(
                originalTitle: item.title,
                maximumCharacters: item.maximumCharacters
            )

            XCTAssertFalse(compacted.isEmpty, item.title)
            XCTAssertLessThanOrEqual(compacted.count, item.maximumCharacters, item.title)
            XCTAssertFalse(compacted.contains("…"), item.title)
            XCTAssertFalse(compacted.hasSuffix("..."), item.title)
            XCTAssertNotNil(
                AppleIntelligenceEventTitleRewriter.acceptedTitle(
                    compacted,
                    maximumCharacters: item.maximumCharacters
                ),
                item.title
            )
        }
    }

    func testCachedTitleWithNoSourceEvidenceIsRegenerated() {
        var cache = EventTitleRewriteCacheSnapshot.empty
        let now = Date(timeIntervalSince1970: 1_000)
        cache.record(
            title: "Team lunch",
            for: "event-key",
            sourceFingerprint: "source-a",
            maximumCharacters: 26,
            now: now
        )

        XCTAssertNil(
            cache.reusableTitle(
                for: "event-key",
                sourceFingerprint: "source-a",
                maximumCharacters: 26,
                now: now,
                originalTitle: "GeoGuessr World Championship — Finals Day"
            )
        )
    }

    func testMeaningChangingSignalsHandleInflectionsWithoutMergingCompetitionStages() {
        XCTAssertFalse(
            EventTitleSemanticSignals.preserves(
                sourceTerm: "cancel",
                candidateIdentities: ["cancellation"]
            )
        )

        let request = EventTitleRewriteRequest(
            title: "GeoGuessr World Championship — Semifinals Day",
            maximumCharacters: 26
        )
        XCTAssertNil(
            AppleIntelligenceEventTitleRewriter.acceptedTitle(
                "GeoGuessr Finals Day",
                for: request
            )
        )
        XCTAssertNotNil(
            AppleIntelligenceEventTitleRewriter.acceptedTitle(
                "GeoGuessr Semifinals Day",
                for: request
            )
        )
    }

    func testPresentationResolverRequestsVisualFallbackWhenMeaningCannotFit() {
        let presentation = EventTitlePresentationResolver.resolve(
            originalTitle: "Quarterly planning with product and operations",
            rewrittenTitle: "Quarterly planning",
            maximumCharacters: 12,
            isEnabled: true,
            isBirthday: false
        )

        XCTAssertFalse(presentation.usesResolvedTitle)
        XCTAssertEqual(presentation.title, "Quarterly planning with product and operations")
    }

    func testBirthdayPresentationUsesKnownCalendarContextWithoutModelRewrite() {
        let presentation = EventTitlePresentationResolver.resolve(
            originalTitle: "Carlos Angulo’s 32nd Birthday",
            rewrittenTitle: "Unrelated meeting",
            maximumCharacters: 20,
            isEnabled: true,
            isBirthday: true
        )

        XCTAssertEqual(presentation.title, "Carlos Angulo Bday")
        XCTAssertLessThanOrEqual(presentation.title.count, 20)
        XCTAssertEqual(
            MenuContentView.compactBirthdayTitle("Carlos Angulo’s 32nd Birthday"),
            "Carlos Angulo"
        )
    }
}
