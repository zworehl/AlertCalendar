import AppKit
import EventKit
import Foundation
import XCTest
@testable import AlertCalendar

final class AgendaSummaryAttachmentPreviewTests: XCTestCase {
    func testCalendarItemAdapterFindsNativeEventKitAttachment() throws {
        let fileURL = try temporaryFile(
            name: "native-brief.txt",
            contents: "Prepare the release checklist."
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let attachmentType = try XCTUnwrap(
            NSClassFromString("EKAttachment") as? NSObject.Type
        )
        let attachment = attachmentType.init()
        attachment.setValue(fileURL.lastPathComponent, forKey: "fileNameRaw")
        attachment.setValue(fileURL, forKey: "URLForPendingFileCopy")

        let event = EKEvent(eventStore: EKEventStore())
        let addAttachmentSelector = NSSelectorFromString("addAttachment:")
        XCTAssertTrue(event.responds(to: addAttachmentSelector))
        event.perform(addAttachmentSelector, with: attachment)

        let references = CalendarMonitor.agendaSummaryAttachments(for: event)

        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(references.first?.fileName, "native-brief.txt")
        XCTAssertEqual(references.first?.localURL, fileURL)
    }

    func testPreviewClientReadsLocalTextAndRedactsContactData() async throws {
        let fileURL = try temporaryFile(
            name: "launch-brief.txt",
            contents: "Review the launch checklist at https://example.com/private with owner@example.com."
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let item = upcomingItem(
            attachment: AgendaSummaryAttachmentReference(
                fileName: "launch-brief.txt",
                localURL: fileURL,
                contentType: "public.plain-text"
            )
        )
        let request = AgendaSummaryRequest(now: item.date, upcomingItems: [item])
        let client = AgendaSummaryAttachmentPreviewClient()
        let directPreviews = await client.contexts(
            for: AttachmentContextRequest(
                references: item.agendaSummaryAttachments,
                referenceText: [item.title],
                maximumCharactersPerAttachment: 2_400,
                maximumTotalCharacters: 6_000,
                maximumContexts: 6
            )
        )
        let enriched = await client.requestByAddingAttachmentPreviews(request)

        let preview = try XCTUnwrap(enriched.items.first?.attachmentPreviews.first)
        XCTAssertEqual(
            directPreviews.map {
                $0.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            },
            [preview]
        )
        XCTAssertEqual(
            preview,
            "Attachment launch-brief.txt relevant excerpts: Review the launch checklist at [link] with [email]."
        )
        XCTAssertFalse(preview.contains(fileURL.path))
        XCTAssertEqual(enriched.items.first?.attachmentNames, ["launch-brief.txt"])
    }

    func testUnsupportedAttachmentStillProvidesNameWithoutReadingBytes() async throws {
        let fileURL = try temporaryFile(name: "diagram.png", contents: "not image text")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let item = upcomingItem(
            attachment: AgendaSummaryAttachmentReference(
                fileName: "diagram.png",
                localURL: fileURL,
                contentType: "public.png"
            )
        )
        let request = AgendaSummaryRequest(now: item.date, upcomingItems: [item])
        let enriched = await AgendaSummaryAttachmentPreviewClient()
            .requestByAddingAttachmentPreviews(request)

        XCTAssertEqual(enriched.items.first?.attachmentNames, ["diagram.png"])
        XCTAssertEqual(enriched.items.first?.hasAttachment, true)
        XCTAssertEqual(enriched.items.first?.attachmentPreviews, [])
    }

    func testTitleContextFindsRelevantFactsAtEndOfLongAttachment() async throws {
        let filler = (0..<500)
            .map { "Administrative background section \($0) with general information." }
            .joined(separator: "\n")
        let fileURL = try temporaryFile(
            name: "enrollment.txt",
            contents: """
            \(filler)
            Identification: 702070452
            Test type: Motorcycle theory test
            Course: SUFICIENCIA MOTOS
            """
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let contexts = await AgendaSummaryAttachmentPreviewClient().contexts(
            for: AttachmentContextRequest(
                references: [
                    AgendaSummaryAttachmentReference(
                        fileName: "enrollment.txt",
                        localURL: fileURL,
                        contentType: "public.plain-text"
                    ),
                ],
                referenceText: ["Ratón's driving license test"],
                maximumCharactersPerAttachment: 900,
                maximumTotalCharacters: 900,
                maximumContexts: 1
            )
        )

        let context = try XCTUnwrap(contexts.first)
        XCTAssertTrue(context.contains("Motorcycle theory test"))
        XCTAssertTrue(context.contains("SUFICIENCIA MOTOS"))
        XCTAssertFalse(context.contains("702070452"))
        XCTAssertTrue(context.contains("[number]"))
    }

    func testUnreadableAttachmentsDoNotConsumeUsefulContextSlots() async throws {
        let unsupportedURL = try temporaryFile(name: "diagram.png", contents: "not an image")
        let usefulURL = try temporaryFile(
            name: "reservation.txt",
            contents: "Reservation type: Overnight sleeper train"
        )
        defer {
            try? FileManager.default.removeItem(at: unsupportedURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: usefulURL.deletingLastPathComponent())
        }

        let contexts = await AgendaSummaryAttachmentPreviewClient().contexts(
            for: AttachmentContextRequest(
                references: [
                    AgendaSummaryAttachmentReference(
                        fileName: "diagram.png",
                        localURL: unsupportedURL,
                        contentType: "public.png"
                    ),
                    AgendaSummaryAttachmentReference(
                        fileName: "reservation.txt",
                        localURL: usefulURL,
                        contentType: "public.plain-text"
                    ),
                ],
                referenceText: ["Long train reservation title"],
                maximumCharactersPerAttachment: 800,
                maximumTotalCharacters: 800,
                maximumContexts: 1
            )
        )

        XCTAssertEqual(contexts.count, 1)
        XCTAssertTrue(contexts[0].contains("Overnight sleeper train"))
    }

    func testImageAttachmentUsesOnDeviceOCR() async throws {
        let fileURL = try temporaryImage(
            name: "exam.png",
            text: "MOTORCYCLE THEORY TEST"
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let contexts = await AgendaSummaryAttachmentPreviewClient().contexts(
            for: AttachmentContextRequest(
                references: [
                    AgendaSummaryAttachmentReference(
                        fileName: "exam.png",
                        localURL: fileURL,
                        contentType: "public.png"
                    ),
                ],
                referenceText: ["Driving license test"],
                maximumCharactersPerAttachment: 800,
                maximumTotalCharacters: 800,
                maximumContexts: 1
            )
        )

        let recognizedText = try XCTUnwrap(contexts.first).lowercased()
        XCTAssertTrue(recognizedText.contains("motorcycle"))
        XCTAssertTrue(recognizedText.contains("theory test"))
    }

    private func temporaryFile(name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    private func temporaryImage(name: String, text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let image = NSImage(size: NSSize(width: 900, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 180).fill()
        text.draw(
            at: NSPoint(x: 40, y: 65),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
        )
        image.unlockFocus()

        let representation = try XCTUnwrap(
            image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        )
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        let fileURL = directory.appendingPathComponent(name)
        try data.write(to: fileURL)
        return fileURL
    }

    private func upcomingItem(
        attachment: AgendaSummaryAttachmentReference
    ) -> UpcomingItem {
        UpcomingItem(
            id: "attachment-event",
            title: "Launch review",
            date: Date(timeIntervalSince1970: 1_776_427_200),
            endDate: nil,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            agendaSummaryAttachments: [attachment],
            hasDocumentIndicator: true,
            calendarID: "work",
            calendarName: "Work",
            calendarColor: .systemBlue,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }
}
