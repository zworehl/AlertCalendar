import CryptoKit
import Foundation

struct EventTitleRewriteCacheEntry: Codable, Equatable, Sendable {
    let sourceFingerprint: String
    let title: String
    var lastMaximumCharacters: Int
    var lastUsedAt: Date
}

struct EventTitleRewriteCacheSnapshot: Codable, Equatable, Sendable {
    // Re-evaluate fragments and use descriptions when refining generic titles.
    static let currentVersion = 11
    static let maximumEntries = 256

    let version: Int
    private(set) var entries: [String: EventTitleRewriteCacheEntry]

    static let empty = EventTitleRewriteCacheSnapshot(
        version: currentVersion,
        entries: [:]
    )

    func hasMatchingSource(for itemKey: String, sourceFingerprint: String) -> Bool {
        entries[itemKey]?.sourceFingerprint == sourceFingerprint
    }

    mutating func reusableTitle(
        for itemKey: String,
        sourceFingerprint: String,
        maximumCharacters: Int,
        now: Date,
        originalTitle: String? = nil
    ) -> String? {
        guard var entry = entries[itemKey],
              entry.sourceFingerprint == sourceFingerprint,
              maximumCharacters <= entry.lastMaximumCharacters,
              AppleIntelligenceEventTitleRewriter.acceptedTitle(
                  entry.title,
                  maximumCharacters: maximumCharacters
              ) != nil else {
            return nil
        }
        if let originalTitle,
           AppleIntelligenceEventTitleRewriter.acceptedTitle(
               entry.title,
               for: EventTitleRewriteRequest(
                   title: originalTitle,
                   maximumCharacters: maximumCharacters
               )
           ) == nil {
            return nil
        }

        entry.lastMaximumCharacters = maximumCharacters
        entry.lastUsedAt = now
        entries[itemKey] = entry
        return entry.title
    }

    mutating func record(
        title: String,
        for itemKey: String,
        sourceFingerprint: String,
        maximumCharacters: Int,
        now: Date
    ) {
        entries[itemKey] = EventTitleRewriteCacheEntry(
            sourceFingerprint: sourceFingerprint,
            title: title,
            lastMaximumCharacters: maximumCharacters,
            lastUsedAt: now
        )
        pruneIfNeeded()
    }

    private mutating func pruneIfNeeded() {
        guard entries.count > Self.maximumEntries else { return }
        let keysToRemove = entries
            .sorted { left, right in
                if left.value.lastUsedAt != right.value.lastUsedAt {
                    return left.value.lastUsedAt < right.value.lastUsedAt
                }
                return left.key < right.key
            }
            .prefix(entries.count - Self.maximumEntries)
            .map(\.key)
        for key in keysToRemove {
            entries.removeValue(forKey: key)
        }
    }
}

struct EventTitleRewriteCacheStore: Sendable {
    let fileURL: URL

    static func defaultStore() -> EventTitleRewriteCacheStore {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return EventTitleRewriteCacheStore(
            fileURL: applicationSupportURL
                .appendingPathComponent("AlertCalendar", isDirectory: true)
                .appendingPathComponent("event-title-rewrite-cache.json")
        )
    }

    func load() -> EventTitleRewriteCacheSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(
                EventTitleRewriteCacheSnapshot.self,
                from: data
              ),
              snapshot.version == EventTitleRewriteCacheSnapshot.currentVersion else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: EventTitleRewriteCacheSnapshot) {
        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(snapshot).write(to: fileURL, options: [.atomic])
        } catch {
            return
        }
    }
}

enum EventTitleRewriteSourceFingerprint {
    static func make(
        for item: UpcomingItem,
        mailContexts: [String] = []
    ) -> String {
        let payload = Payload(item: item, mailContexts: mailContexts)
        guard let data = try? JSONEncoder.alertCalendarStable.encode(payload) else {
            return ""
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONEncoder {
    static var alertCalendarStable: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

private extension EventTitleRewriteSourceFingerprint {
    struct Payload: Encodable {
        let id: String
        let title: String
        let startsAt: Date
        let endsAt: Date?
        let isAllDay: Bool
        let location: String?
        let meetingURL: String?
        let openLinkURL: String?
        let urlHosts: [String]
        let linkedURLs: [String]
        let attachments: [Attachment]
        let organizer: Participant?
        let attendees: [Participant]
        let participationStatus: String?
        let isRecurring: Bool
        let description: String?
        let calendarID: String?
        let calendarName: String
        let itemKind: String
        let lastModifiedAt: Date?
        let mailContexts: [String]

        init(item: UpcomingItem, mailContexts: [String]) {
            id = item.id
            title = item.title
            startsAt = item.date
            endsAt = item.endDate
            isAllDay = item.isAllDay
            location = item.locationText
            meetingURL = item.meetingURL?.absoluteString
            openLinkURL = item.openLinkURL?.absoluteString
            urlHosts = item.urlHosts
            linkedURLs = item.agendaSummaryURLCandidates.map(\.absoluteString)
            attachments = item.agendaSummaryAttachments.map(Attachment.init)
            organizer = item.organizer.map(Participant.init)
            attendees = item.attendees.map(Participant.init)
            participationStatus = item.eventParticipationStatus?.rawValue
            isRecurring = item.isRecurring
            description = item.descriptionText
            calendarID = item.calendarID
            calendarName = item.calendarName
            itemKind = item.kind.rawValue
            lastModifiedAt = item.lastModifiedAt
            self.mailContexts = mailContexts.sorted()
        }
    }

    struct Attachment: Encodable {
        let fileName: String
        let contentType: String?
        let fileSize: Int?

        init(_ attachment: AgendaSummaryAttachmentReference) {
            fileName = attachment.fileName
            contentType = attachment.contentType
            let values: URLResourceValues?
            if let localURL = attachment.localURL {
                values = try? localURL.resourceValues(
                    forKeys: [.fileSizeKey]
                )
            } else {
                values = nil
            }
            fileSize = values?.fileSize
        }
    }

    struct Participant: Encodable {
        let id: String?
        let displayText: String
        let emailAddress: String?
        let response: String?

        init(_ organizer: MeetingOrganizer) {
            id = nil
            displayText = organizer.displayText
            emailAddress = organizer.emailAddress
            response = nil
        }

        init(_ attendee: MeetingAttendee) {
            id = attendee.id
            displayText = attendee.displayText
            emailAddress = attendee.emailAddress
            response = attendee.response.rawValue
        }
    }
}
