import EventKit
import Foundation

extension CalendarMonitor {
    /// EventKit does not publish attachment access in its SDK, but Calendar-backed
    /// items expose the relationship at runtime on macOS. Keep that dependency
    /// isolated and optional so a future system change simply yields no previews.
    nonisolated static func agendaSummaryAttachments(
        for calendarItem: EKCalendarItem
    ) -> [AgendaSummaryAttachmentReference] {
        let attachmentsSelector = NSSelectorFromString("attachments")
        guard calendarItem.responds(to: attachmentsSelector),
              let rawAttachments = calendarItem.perform(attachmentsSelector)?.takeUnretainedValue() else {
            return []
        }

        let attachmentObjects: [NSObject]
        if let attachments = rawAttachments as? NSArray {
            attachmentObjects = attachments.compactMap { $0 as? NSObject }
        } else if let attachments = rawAttachments as? NSSet {
            attachmentObjects = attachments.compactMap { $0 as? NSObject }
        } else {
            return []
        }

        var seenReferences: Set<AgendaSummaryAttachmentReference> = []
        return attachmentObjects.enumerated().compactMap { offset, attachment in
            let localURL = attachmentFileURL(from: attachment)
            let rawFileName = attachmentStringValue(attachment, selectorName: "fileName")
                ?? localURL?.lastPathComponent
                ?? "Attachment \(offset + 1)"
            let fileName = boundedAttachmentMetadata(rawFileName, maximumLength: 120)
            guard !fileName.isEmpty else { return nil }

            let contentType = attachmentStringValue(attachment, selectorName: "contentType")
                ?? attachmentStringValue(attachment, selectorName: "fileFormat")
            let reference = AgendaSummaryAttachmentReference(
                fileName: fileName,
                localURL: localURL,
                contentType: contentType.map {
                    boundedAttachmentMetadata($0, maximumLength: 100)
                }
            )
            return seenReferences.insert(reference).inserted ? reference : nil
        }
    }

    nonisolated private static func attachmentFileURL(from attachment: NSObject) -> URL? {
        for selectorName in [
            "securityScopedLocalURLWrapper",
            "securityScopedLocalURLForArchivedDataWrapper",
            "localURL",
            "urlOnDisk",
            "URL",
        ] {
            guard let value = attachmentObjectValue(
                attachment,
                selectorName: selectorName
            ) else { continue }
            if let url = localFileURL(from: value, recursionDepth: 0) {
                return url
            }
        }
        return nil
    }

    nonisolated private static func localFileURL(
        from value: AnyObject,
        recursionDepth: Int
    ) -> URL? {
        if let url = value as? URL {
            return url.isFileURL ? url : nil
        }
        if let path = value as? String, path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        guard recursionDepth == 0, let wrapper = value as? NSObject else { return nil }
        for selectorName in ["url", "URL", "fileURL"] {
            guard let wrappedValue = attachmentObjectValue(
                wrapper,
                selectorName: selectorName
            ) else { continue }
            if let url = localFileURL(from: wrappedValue, recursionDepth: recursionDepth + 1) {
                return url
            }
        }
        return nil
    }

    nonisolated private static func attachmentStringValue(
        _ object: NSObject,
        selectorName: String
    ) -> String? {
        guard let value = attachmentObjectValue(object, selectorName: selectorName) else {
            return nil
        }
        if let string = value as? String {
            return AlertCalendarString.trimmedNonEmpty(string)
        }
        if let typedValue = value as? NSObject,
           let identifier = attachmentObjectValue(
                typedValue,
                selectorName: "identifier"
           ) as? String {
            return AlertCalendarString.trimmedNonEmpty(identifier)
        }
        return nil
    }

    nonisolated private static func attachmentObjectValue(
        _ object: NSObject,
        selectorName: String
    ) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    nonisolated private static func boundedAttachmentMetadata(
        _ value: String,
        maximumLength: Int
    ) -> String {
        let normalized = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.count <= maximumLength
            ? normalized
            : String(normalized.prefix(maximumLength))
    }
}
