import AppKit
import Foundation
import XCTest
@testable import AlertCalendar

private actor AgendaSummaryDraftQueue {
    private var drafts: [AppleIntelligenceAgendaSummaryClient.Draft]

    init(_ drafts: [AppleIntelligenceAgendaSummaryClient.Draft]) {
        self.drafts = drafts
    }

    func next() throws -> AppleIntelligenceAgendaSummaryClient.Draft {
        guard !drafts.isEmpty else {
            throw AgendaSummaryDraftQueueError.empty
        }
        return drafts.removeFirst()
    }
}

private enum AgendaSummaryDraftQueueError: Error {
    case empty
}

final class AppleIntelligenceAgendaSummaryClientTests: XCTestCase {
    func testGenerateSummarySendsEveryMetadataFieldAndNormalizesOutput() async throws {
        let client = AppleIntelligenceAgendaSummaryClient(
            availabilityProvider: { .available },
            responder: { instructions, prompt in
                XCTAssertTrue(instructions.contains("English"))
                XCTAssertTrue(instructions.contains("no more than 60 words"))
                XCTAssertTrue(instructions.contains("Never use an ellipsis"))
                XCTAssertTrue(instructions.contains("personalized context"))
                XCTAssertTrue(instructions.contains("actionable facts from descriptions"))
                XCTAssertTrue(instructions.contains("Write those facts directly"))
                XCTAssertTrue(instructions.contains("untrusted data"))
                XCTAssertTrue(prompt.contains("exactly 2 visible items"))
                XCTAssertTrue(prompt.contains("\"itemCount\":2"))
                XCTAssertTrue(prompt.contains("\"maximumWords\":60"))
                XCTAssertTrue(prompt.contains("\"index\":1"))
                XCTAssertTrue(prompt.contains("\"index\":2"))
                XCTAssertTrue(prompt.contains("Sprint review"))
                XCTAssertTrue(prompt.contains("Costa_Rica"))
                XCTAssertTrue(prompt.contains("\"recurring\":true"))
                XCTAssertTrue(prompt.contains("\"hasAttachment\":true"))
                XCTAssertTrue(prompt.contains("\"attachmentCount\":1"))
                XCTAssertTrue(prompt.contains("\"attachmentNames\":[\"launch-brief.txt\"]"))
                XCTAssertTrue(prompt.contains("Review the attached launch checklist"))
                XCTAssertTrue(prompt.contains("Read the planning brief before joining."))
                XCTAssertTrue(prompt.contains("Details: [link]"))
                XCTAssertFalse(prompt.contains("https://docs.google.com/document/d/brief"))
                XCTAssertTrue(prompt.contains("\"urlCount\":2"))
                XCTAssertTrue(prompt.contains("\"urlHosts\":[\"docs.google.com\",\"zoom.us\"]"))
                XCTAssertTrue(prompt.contains("\"linkedPagePreviews\":[\"Page title: Launch planning brief.\"]"))
                XCTAssertTrue(prompt.contains("\"hasMeetingURL\":true"))
                XCTAssertTrue(prompt.contains("\"travelTimeMinutes\":18"))
                XCTAssertTrue(prompt.contains("\"location\":\"Downtown clinic\""))
                XCTAssertTrue(prompt.contains("\"hasMapPoint\":true"))
                XCTAssertTrue(prompt.contains("Personalized attendee preview"))
                XCTAssertTrue(prompt.contains("\"clockFormat\":\"12-hour\""))
                XCTAssertTrue(prompt.contains("\"displayStart\":\"7:00 AM\""))
                return .init(
                    summary: "On 2026-04-17, Sprint review starts at 9:00 AM.\n  The dentist appointment follows at 11:00 AM.",
                    coveredItemIndexes: [1, 2]
                )
            }
        )

        let summary = try await client.generateSummary(for: makeRequest())

        XCTAssertEqual(
            summary,
            "Today, Sprint review starts at 9:00 AM. The dentist appointment follows at 11:00 AM."
        )
    }

    func testGenerateSummaryCompactsAnOverlongOrEllipsizedDraft() async throws {
        let longDraft = (1...48).map { "draft\($0)" }.joined(separator: " ") + "..."
        let queue = AgendaSummaryDraftQueue([
            .init(summary: longDraft, coveredItemIndexes: [1, 2]),
            .init(
                summary: "Sprint review comes first, followed by the dentist; both visible items are covered.",
                coveredItemIndexes: [1, 2]
            ),
        ])
        let client = AppleIntelligenceAgendaSummaryClient(
            availabilityProvider: { .available },
            responder: { _, _ in try await queue.next() }
        )

        let summary = try await client.generateSummary(for: makeRequest())

        XCTAssertEqual(
            summary,
            "Sprint review comes first, followed by the dentist; both visible items are covered."
        )
        XCTAssertLessThanOrEqual(summary.split(whereSeparator: \.isWhitespace).count, 60)
        XCTAssertFalse(summary.contains("..."))
        XCTAssertFalse(summary.contains("…"))
    }

    func testGenerateSummaryUsesCompleteFallbackInsteadOfTruncating() async throws {
        let longDraft = (1...48).map { "word\($0)" }.joined(separator: " ")
        let queue = AgendaSummaryDraftQueue([
            .init(summary: longDraft, coveredItemIndexes: [1, 2]),
            .init(summary: longDraft, coveredItemIndexes: [1, 2]),
        ])
        let client = AppleIntelligenceAgendaSummaryClient(
            availabilityProvider: { .available },
            responder: { _, _ in try await queue.next() }
        )

        let summary = try await client.generateSummary(for: makeRequest())

        XCTAssertTrue(summary.hasSuffix("."))
        XCTAssertLessThanOrEqual(summary.split(whereSeparator: \.isWhitespace).count, 60)
        XCTAssertFalse(summary.contains("..."))
        XCTAssertFalse(summary.contains("…"))
        XCTAssertTrue(summary.contains("2 items"))
        XCTAssertTrue(summary.contains("Sprint review"))
        XCTAssertTrue(summary.contains("planning brief"))
        XCTAssertTrue(summary.contains("Dentist"))
        XCTAssertTrue(summary.contains("Downtown clinic"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("relevant context"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("linked-page preview"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("personalized preview"))
    }

    func testGenerateSummaryRewritesMetadataInventoryAsConcreteAgendaCopy() async throws {
        let queue = AgendaSummaryDraftQueue([
            .init(
                summary: "Your agenda has two items. Relevant context includes descriptions and linked-page previews.",
                coveredItemIndexes: [1, 2]
            ),
            .init(
                summary: "Today, review the planning brief before Sprint review at 9:00 AM, then allow 18 minutes to reach the Downtown clinic for the 11:00 AM dentist appointment.",
                coveredItemIndexes: [1, 2]
            ),
        ])
        let client = AppleIntelligenceAgendaSummaryClient(
            availabilityProvider: { .available },
            responder: { instructions, prompt in
                XCTAssertTrue(instructions.contains("never use phrases such as"))
                if prompt.contains("Previous draft") {
                    XCTAssertTrue(prompt.contains("never inventory available context"))
                }
                return try await queue.next()
            }
        )

        let summary = try await client.generateSummary(for: makeRequest())

        XCTAssertTrue(summary.contains("planning brief"))
        XCTAssertTrue(summary.contains("Downtown clinic"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("relevant context"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("linked-page preview"))
    }

    func testGenerateSummaryHonorsThirtyWordSelectionDuringCompaction() async throws {
        let overlongDraft = (1...31).map { "word\($0)" }.joined(separator: " ") + "."
        let queue = AgendaSummaryDraftQueue([
            .init(summary: overlongDraft, coveredItemIndexes: [1, 2]),
            .init(
                summary: "Today, Sprint review uses the planning brief at 9:00 AM; the dentist follows at 11:00 AM after 18 minutes of travel.",
                coveredItemIndexes: [1, 2]
            ),
        ])
        let client = AppleIntelligenceAgendaSummaryClient(
            availabilityProvider: { .available },
            responder: { instructions, prompt in
                XCTAssertTrue(instructions.contains("no more than 30 words"))
                if prompt.contains("Previous draft") {
                    XCTAssertTrue(prompt.contains("at most 25 words"))
                }
                return try await queue.next()
            }
        )
        let baseRequest = makeRequest()
        let request = AgendaSummaryRequest(
            now: baseRequest.now,
            timeZone: TimeZone(identifier: baseRequest.timeZoneIdentifier)!,
            locale: Locale(identifier: "en_US"),
            maximumWords: 30,
            upcomingItems: [
                makeItem(id: "first", title: "Sprint review", start: baseRequest.items[0].startsAt),
                makeItem(id: "second", title: "Dentist", start: baseRequest.items[1].startsAt),
            ]
        )

        let summary = try await client.generateSummary(for: request)

        XCTAssertLessThanOrEqual(summary.split(whereSeparator: \.isWhitespace).count, 30)
    }

    func testUnavailableClientDoesNotAttemptGeneration() async {
        let client = AppleIntelligenceAgendaSummaryClient(
            availabilityProvider: { .appleIntelligenceNotEnabled },
            responder: { _, _ in
                XCTFail("The model must not be invoked when Apple Intelligence is unavailable")
                return .init(summary: "Unexpected", coveredItemIndexes: [])
            }
        )

        do {
            _ = try await client.generateSummary(for: makeRequest())
            XCTFail("Expected unavailable generation to fail")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    func testAvailabilityProvidesSettingsOnlyAlertCopy() {
        XCTAssertNil(AgendaSummaryAvailability.available.settingsAlertMessage)
        XCTAssertTrue(
            AgendaSummaryAvailability.appleIntelligenceNotEnabled.settingsAlertMessage?
                .contains("System Settings") == true
        )
        XCTAssertTrue(
            AgendaSummaryAvailability.modelNotReady.settingsAlertMessage?
                .contains("automatically") == true
        )
    }

    func testPresentationPolicyRequestsAvailableSummary() {
        XCTAssertEqual(
            AgendaSummaryPresentationAction.resolve(
                isEnabled: true,
                availability: .available,
                requestFingerprint: 42
            ),
            .request(fingerprint: 42)
        )
    }

    func testPresentationPolicyCancelsOnlyWhenSummaryCannotBeUsed() {
        XCTAssertEqual(
            AgendaSummaryPresentationAction.resolve(
                isEnabled: false,
                availability: .available,
                requestFingerprint: 42
            ),
            .cancel
        )
        XCTAssertEqual(
            AgendaSummaryPresentationAction.resolve(
                isEnabled: true,
                availability: .modelNotReady,
                requestFingerprint: 42
            ),
            .cancel
        )
    }

    func testAgendaSummaryRetriesUseBoundedBackoff() {
        XCTAssertEqual(CalendarMonitor.agendaSummaryRetryDelay(forAttempt: 0), 60)
        XCTAssertEqual(CalendarMonitor.agendaSummaryRetryDelay(forAttempt: 1), 5 * 60)
        XCTAssertEqual(CalendarMonitor.agendaSummaryRetryDelay(forAttempt: 2), 15 * 60)
        XCTAssertNil(CalendarMonitor.agendaSummaryRetryDelay(forAttempt: 3))
        XCTAssertNil(CalendarMonitor.agendaSummaryRetryDelay(forAttempt: -1))
    }

    func testAgendaSummaryRequestSortsAllItemsAndKeepsFingerprintUntilVisibleListChanges() {
        let now = Date(timeIntervalSince1970: 1_776_427_200)
        let items = (0..<20).reversed().map { index in
            makeItem(
                id: "item-\(index)",
                title: "Item \(index)",
                start: now.addingTimeInterval(Double(index) * 60)
            )
        }

        let request = AgendaSummaryRequest(
            now: now,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            upcomingItems: items
        )

        XCTAssertEqual(request.items.count, 20)
        XCTAssertEqual(request.items.first?.title, "Item 0")
        XCTAssertEqual(request.items.last?.title, "Item 19")

        let shortlyAfter = AgendaSummaryRequest(
            now: now.addingTimeInterval(60),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            upcomingItems: items
        )
        let muchLater = AgendaSummaryRequest(
            now: now.addingTimeInterval(24 * 60 * 60),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            upcomingItems: items
        )
        XCTAssertEqual(request.fingerprint, shortlyAfter.fingerprint)
        XCTAssertEqual(request.fingerprint, muchLater.fingerprint)
    }

    func testAgendaSummaryFingerprintChangesWhenVisibleItemsChange() {
        let now = Date(timeIntervalSince1970: 1_776_427_200)
        let firstItem = makeItem(id: "first", title: "First", start: now)
        let secondItem = makeItem(id: "second", title: "Second", start: now.addingTimeInterval(60))
        let initialRequest = AgendaSummaryRequest(now: now, upcomingItems: [firstItem])
        let addedRequest = AgendaSummaryRequest(now: now, upcomingItems: [firstItem, secondItem])
        let advancedRequest = AgendaSummaryRequest(now: now, upcomingItems: [secondItem])

        XCTAssertNotEqual(initialRequest.fingerprint, addedRequest.fingerprint)
        XCTAssertNotEqual(addedRequest.fingerprint, advancedRequest.fingerprint)
    }

    func testAgendaSummaryFingerprintChangesWhenMaximumWordSelectionChanges() {
        let now = Date(timeIntervalSince1970: 1_776_427_200)
        let item = makeItem(id: "review", title: "Sprint review", start: now)
        let shortRequest = AgendaSummaryRequest(now: now, maximumWords: 30, upcomingItems: [item])
        let longRequest = AgendaSummaryRequest(now: now, maximumWords: 100, upcomingItems: [item])

        XCTAssertEqual(AgendaSummaryRequest(now: now, upcomingItems: [item]).maximumWords, 60)
        XCTAssertNotEqual(shortRequest.fingerprint, longRequest.fingerprint)
    }

    func testAgendaSummaryGenerationFingerprintTracksLinkedPagePreviewSetting() {
        let request = makeRequest()

        XCTAssertEqual(
            request.generationFingerprint(usesLinkedPagePreviews: false),
            request.generationFingerprint(usesLinkedPagePreviews: false)
        )
        XCTAssertNotEqual(
            request.generationFingerprint(usesLinkedPagePreviews: false),
            request.generationFingerprint(usesLinkedPagePreviews: true)
        )
    }

    func testAgendaSummaryFingerprintChangesWhenEventMetadataChanges() {
        let now = Date(timeIntervalSince1970: 1_776_427_200)
        let original = makeItem(
            id: "review",
            title: "Sprint review",
            start: now,
            descriptionText: "Review the launch checklist.",
            urlCount: 1,
            urlHosts: ["docs.google.com"]
        )
        let updated = makeItem(
            id: "review",
            title: "Sprint review",
            start: now,
            descriptionText: "Bring the final launch decision.",
            urlCount: 2,
            urlHosts: ["docs.google.com", "jira.example.com"]
        )

        let originalRequest = AgendaSummaryRequest(now: now, upcomingItems: [original])
        let updatedRequest = AgendaSummaryRequest(now: now, upcomingItems: [updated])

        XCTAssertNotEqual(originalRequest.fingerprint, updatedRequest.fingerprint)
        XCTAssertEqual(updatedRequest.items.first?.description, "Bring the final launch decision.")
        XCTAssertEqual(updatedRequest.items.first?.urlHosts, ["docs.google.com", "jira.example.com"])
    }

    func testAgendaSummaryExcludesAstronomyItems() {
        let now = Date(timeIntervalSince1970: 1_776_427_200)
        let request = AgendaSummaryRequest(
            now: now,
            upcomingItems: [
                makeItem(id: "work", title: "Sprint review", start: now),
                makeItem(id: "sunrise", title: "Sunrise", start: now, calendarName: "Astronomy"),
                makeItem(id: "sunset", title: "Sunset", start: now, calendarName: "Personal"),
            ]
        )

        XCTAssertEqual(request.items.map(\.title), ["Sprint review"])
    }

    func testAgendaSummaryItemsMatchVisibleItemsWithoutDuplicates() {
        let now = Date(timeIntervalSince1970: 1_776_427_200)
        let contextualItem = makeItem(id: "contextual", title: "Current meeting", start: now)
        let queueItem = makeItem(id: "queue", title: "Next meeting", start: now.addingTimeInterval(60))

        let items = MenuContentView.agendaSummaryItems(
            contextualItems: [contextualItem],
            queueItems: [contextualItem, queueItem]
        )

        XCTAssertEqual(items.map(\.notificationKey), [
            contextualItem.notificationKey,
            queueItem.notificationKey,
        ])
    }

    func testAgendaSummaryPersonalizedContextUsesExistingPreview() {
        let item = makeItem(
            id: "location",
            title: "Site visit",
            start: Date(timeIntervalSince1970: 1_776_427_200)
        )

        let context = MenuContentView.agendaSummaryPersonalizedContext(
            for: item,
            previewKind: .location("Central Park")
        )

        XCTAssertEqual(context, "Personalized location and map preview for Central Park.")
    }

    func testCalendarItemURLMetadataDeduplicatesLinksAndKeepsHosts() {
        let eventURL = URL(string: "https://docs.google.com/document/d/brief")!
        let meetingURL = URL(string: "https://zoom.us/j/123")!

        let metadata = CalendarMonitor.calendarItemURLMetadata(
            eventURL: eventURL,
            notes: "Brief: https://docs.google.com/document/d/brief Join: https://zoom.us/j/123",
            meetingURL: meetingURL
        )

        XCTAssertEqual(metadata.count, 2)
        XCTAssertEqual(metadata.hosts, ["docs.google.com", "zoom.us"])
    }

    func testAgendaSummaryURLCandidatesExcludeMeetingLinksAndFiles() {
        let documentURL = URL(string: "https://docs.google.com/document/d/brief")!
        let meetingURL = URL(string: "https://zoom.us/j/123")!

        let candidates = CalendarMonitor.agendaSummaryURLCandidates(
            eventURL: documentURL,
            notes: "Join https://zoom.us/j/123 or open file:///tmp/private.txt",
            meetingURL: meetingURL
        )

        XCTAssertEqual(candidates, [documentURL])
    }

    func testAgendaSummaryURLCandidatesKeepsEveryEligibleLink() {
        let eventURL = URL(string: "https://example.com/event")!
        let firstNoteURL = URL(string: "https://example.com/first")!
        let secondNoteURL = URL(string: "https://example.com/second")!
        let thirdNoteURL = URL(string: "https://example.com/third")!
        let fourthNoteURL = URL(string: "https://example.com/fourth")!

        let candidates = CalendarMonitor.agendaSummaryURLCandidates(
            eventURL: eventURL,
            notes: """
            \(firstNoteURL.absoluteString) \(secondNoteURL.absoluteString)
            \(thirdNoteURL.absoluteString) \(fourthNoteURL.absoluteString)
            """,
            meetingURL: nil
        )

        XCTAssertEqual(
            candidates,
            [eventURL, firstNoteURL, secondNoteURL, thirdNoteURL, fourthNoteURL]
        )
    }

    func testPreferredOpenLinkUsesUnknownLocationURLInsteadOfTreatingItAsMeeting() {
        let unknownProviderURL = URL(string: "https://events.example.com/session/launch-review")!

        let openLink = CalendarMonitor.preferredOpenLinkURL(
            eventURL: nil,
            notes: nil,
            location: unknownProviderURL.absoluteString,
            meetingURL: nil
        )

        XCTAssertEqual(openLink, unknownProviderURL)
    }

    func testPreferredOpenLinkExcludesRecognizedMeetingURL() {
        let meetingURL = URL(string: "https://meet.google.com/abc-defg-hij")!

        let openLink = CalendarMonitor.preferredOpenLinkURL(
            eventURL: meetingURL,
            notes: nil,
            location: meetingURL.absoluteString,
            meetingURL: meetingURL
        )

        XCTAssertNil(openLink)
    }

    func testURLMetadataIncludesUnknownLinkStoredAsEventLocation() {
        let metadata = CalendarMonitor.calendarItemURLMetadata(
            eventURL: nil,
            notes: nil,
            location: "Details: https://events.example.com/session/launch-review",
            meetingURL: nil
        )

        XCTAssertEqual(metadata.count, 1)
        XCTAssertEqual(metadata.hosts, ["events.example.com"])
    }

    private func makeRequest() -> AgendaSummaryRequest {
        let now = Date(timeIntervalSince1970: 1_776_427_200)
        let sprintReview = makeItem(
            id: "sprint",
            title: "Sprint review",
            start: now.addingTimeInterval(3_600),
            isRecurring: true,
            hasDocumentIndicator: true,
            descriptionText: " Read the planning brief\n before joining. Details: https://docs.google.com/document/d/brief ",
            meetingURL: URL(string: "https://zoom.us/j/123")!,
            urlCount: 2,
            urlHosts: ["zoom.us", "docs.google.com"],
            agendaSummaryURLCandidates: [
                URL(string: "https://docs.google.com/document/d/brief")!,
            ],
            agendaSummaryAttachments: [
                AgendaSummaryAttachmentReference(
                    fileName: "launch-brief.txt",
                    localURL: nil,
                    contentType: "public.plain-text"
                ),
            ]
        )
        let dentist = makeItem(
            id: "dentist",
            title: "Dentist",
            start: now.addingTimeInterval(10_800),
            travelTimeMinutes: 18,
            locationText: "Downtown clinic",
            locationCoordinate: ResolvedLocationCoordinate(latitude: 9.93, longitude: -84.08)
        )
        let request = AgendaSummaryRequest(
            now: now,
            timeZone: TimeZone(identifier: "America/Costa_Rica")!,
            locale: Locale(identifier: "en_US"),
            upcomingItems: [sprintReview, dentist],
            personalizedContextByItemKey: [
                sprintReview.notificationKey: "Personalized attendee preview with response context.",
            ]
        )
        return request
            .addingAttachmentPreviews([
                sprintReview.notificationKey: ["Review the attached launch checklist."],
            ])
            .addingLinkedPagePreviews([
                sprintReview.notificationKey: ["Page title: Launch planning brief."],
            ])
    }

    private func makeItem(
        id: String,
        title: String,
        start: Date,
        isAllDay: Bool = false,
        isRecurring: Bool = false,
        hasDocumentIndicator: Bool = false,
        descriptionText: String? = nil,
        meetingURL: URL? = nil,
        urlCount: Int? = nil,
        urlHosts: [String] = [],
        agendaSummaryURLCandidates: [URL] = [],
        agendaSummaryAttachments: [AgendaSummaryAttachmentReference] = [],
        travelTimeMinutes: Int? = nil,
        locationText: String? = nil,
        locationCoordinate: ResolvedLocationCoordinate? = nil,
        calendarName: String = "Work"
    ) -> UpcomingItem {
        UpcomingItem(
            id: id,
            title: title,
            date: start,
            endDate: start.addingTimeInterval(45 * 60),
            isAllDay: isAllDay,
            showsMutedBackground: false,
            travelTimeMinutes: travelTimeMinutes,
            locationText: locationText,
            locationCoordinate: locationCoordinate,
            meetingURL: meetingURL,
            urlCount: urlCount,
            urlHosts: urlHosts,
            agendaSummaryURLCandidates: agendaSummaryURLCandidates,
            agendaSummaryAttachments: agendaSummaryAttachments,
            isRecurring: isRecurring,
            hasDocumentIndicator: hasDocumentIndicator,
            descriptionText: descriptionText,
            calendarID: "work",
            calendarName: calendarName,
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }
}
