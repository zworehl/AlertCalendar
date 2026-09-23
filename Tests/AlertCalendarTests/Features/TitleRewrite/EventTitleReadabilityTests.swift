import XCTest
@testable import AlertCalendar

final class EventTitleReadabilityTests: XCTestCase {
    func testRejectsIncompleteActivitiesAndPromotionalFragments() {
        let cases = [
            ("WHR DRP | WHD-9768 Working Session", "WHR DRP WHD-9768 Working"),
            ("WHR DRP | WHD-9768 Working Session", "WHR DRP WHD-9768 Session"),
            ("WHR DRP | WHD-9768 Working Session", "WHR DRP WHD-9768"),
            ("Apple Event: Surprise and shine", "Apple Event Surprise"),
            ("Apple Event: Surprise and shine", "Apple Event shine"),
            ("Blockbuster Sale: Save big on select digital games!", "Blockbuster Sale Save"),
            ("Blockbuster Sale: Save big on select digital games!", "Blockbuster Sale games"),
            ("Digital Replatform: Zilker Sprint Demo", "Digital Sprint"),
        ]
        for (source, draft) in cases {
            let request = EventTitleRewriteRequest(title: source, maximumCharacters: 24)
            XCTAssertNil(AppleIntelligenceEventTitleRewriter.acceptedTitle(draft, for: request), draft)
            XCTAssertFalse(EventTitlePhraseGuard.rejectionReasons(for: draft, source: source).isEmpty)
        }
    }

    func testLocalFallbackKeepsCompleteUsefulTitles() {
        let cases = [
            ("WHR DRP | WHD-9768 Working Session", "WHD-9768 Working Session"),
            ("Apple Event: Surprise and shine", "Apple Event"),
            ("Blockbuster Sale: Save big on select digital games!", "Blockbuster Sale"),
        ]
        for (source, expected) in cases {
            XCTAssertEqual(EventTitleRewriteResolver.resolvedTitle(
                nil, originalTitle: source, maximumCharacters: 24
            ), expected)
        }
    }

    func testDescriptionAloneCanSupplyThePurposeOfAnIdentifierSession() async throws {
        let request = EventTitleRewriteRequest(
            title: "WHR DRP | WHD-9768 Working Session",
            description: "Reproduce WHD-9768 together and triage the issue in real time.",
            maximumCharacters: 24
        )
        let rewriter = AppleIntelligenceEventTitleRewriter(
            availabilityProvider: { .available },
            responder: { _, prompt in
                if prompt.contains("identifiersHandledByApplication") {
                    XCTAssertTrue(prompt.contains("triage the issue"))
                    return .init(title: "Issue Triage")
                }
                return .init(title: "WHD-9768 Working Session")
            }
        )
        let title = try await rewriter.rewriteTitle(for: request)
        XCTAssertEqual(title, "Triage · WHD-9768")
        let presentation = EventTitlePresentationResolver.resolve(
            originalTitle: request.title, rewrittenTitle: title,
            maximumCharacters: 24, isEnabled: true, isBirthday: false
        )
        XCTAssertEqual(presentation.title, title)
    }

    func testDescriptionFactsPrioritizeRelevantTailAndExcludeJoiningInstructions() {
        let filler = (0..<80).map { "Administrative message \($0)." }.joined(separator: "\n")
        let request = EventTitleRewriteRequest(
            title: "Migration working session",
            description: """
            Join with Google Meet: https://meet.example.com/private
            Or dial: +1 555 123 4567
            \(filler)
            Migration rollback rehearsal with the operations team.
            """,
            maximumCharacters: 24
        )
        let facts = request.distinctiveContextFacts.joined(separator: "\n")
        XCTAssertTrue(facts.contains("rollback rehearsal"))
        XCTAssertFalse(facts.contains("Join with"))
        XCTAssertFalse(facts.contains("Or dial"))
        XCTAssertFalse(facts.contains("https://"))
    }

    func testExtractedNamesUseTheFullSourcesLanguageEvidence() {
        let request = EventTitleRewriteRequest(
            title: "Digital Replatform: Zilker Sprint Demo", maximumCharacters: 24
        )
        XCTAssertEqual(AppleIntelligenceEventTitleRewriter.acceptedTitle(
            "Zilker Sprint Demo", for: request
        ), "Zilker Sprint Demo")
        XCTAssertFalse(EventTitleEnglishRules.supportsRewrite(
            "Reunión trimestral de producto y operaciones", source: "Quarterly product review"
        ))
    }

    func testCacheRechecksFragmentQualityAndRetainsValidNames() {
        for (source, draft, reusable) in [
            ("Apple Event: Surprise and shine", "Apple Event Surprise", false),
            ("WHR DRP | WHD-9768 Working Session", "WHR DRP WHD-9768 Working", false),
            ("Digital Replatform: Zilker Sprint Demo", "Zilker Sprint Demo", true),
        ] {
            var cache = EventTitleRewriteCacheSnapshot.empty
            let now = Date(timeIntervalSince1970: 1_000)
            cache.record(title: draft, for: "event", sourceFingerprint: "source", maximumCharacters: 24, now: now)
            XCTAssertEqual(cache.reusableTitle(
                for: "event", sourceFingerprint: "source", maximumCharacters: 24,
                now: now, originalTitle: source
            ), reusable ? draft : nil)
        }
    }

    func testNamedEventsRetainCompleteSlogansWhenTheyFit() {
        let source = "Apple Event: Surprise and shine"
        XCTAssertNotNil(AppleIntelligenceEventTitleRewriter.acceptedTitle(
            source, for: EventTitleRewriteRequest(title: source, maximumCharacters: 40)
        ))
        XCTAssertNotNil(AppleIntelligenceEventTitleRewriter.acceptedTitle(
            "Project review Phase 2",
            for: EventTitleRewriteRequest(title: "Project review: Phase 2", maximumCharacters: 24)
        ))
    }

    func testUnseenTitlesUseTheSameReadabilityRules() {
        for (source, fragment) in [
            ("OPS CORE | TASK-4821 Working Group", "OPS TASK-4821 Working"),
            ("Orbit Event: Imagine and explore", "Orbit Event Imagine"),
            ("Summer Sale: Discover more great adventures", "Summer Sale Discover"),
            ("Platform Session: Investigate slow database queries", "Platform Investigate"),
            ("Project #1842 Working Session", "#1842"),
            ("task-4821 Working Session", "task-4821"),
        ] {
            XCTAssertFalse(EventTitlePhraseGuard.rejectionReasons(for: fragment, source: source).isEmpty, fragment)
        }
        XCTAssertFalse(EventTitleSyntaxValidator.dropsTrailingModifierObject(
            "Product review", source: "Review the product requirements"
        ))
        XCTAssertTrue(EventTitlePhraseGuard.rejectionReasons(
            for: "TASK-4821 Work Session", source: "OPS CORE | TASK-4821 Working Session"
        ).isEmpty)
        for limit in [10, 16, 20, 24, 32] {
            let source = "OPS CORE | TASK-4821 Working Session"
            let compact = EventTitleSemanticCompactor.compact(title: source, maximumCharacters: limit)
            if compact != source {
                XCTAssertLessThanOrEqual(compact.count, limit)
                XCTAssertNotNil(AppleIntelligenceEventTitleRewriter.acceptedTitle(
                    compact, for: EventTitleRewriteRequest(title: source, maximumCharacters: limit)
                ))
            }
        }
    }
}
