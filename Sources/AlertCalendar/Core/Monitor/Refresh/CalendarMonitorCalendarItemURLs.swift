import EventKit
import Foundation

extension CalendarMonitor {
    func hasDocumentIndicator(for event: EKEvent, meetingURL: URL?) -> Bool {
        Self.hasDocumentIndicator(
            eventURL: event.url,
            notes: event.notes,
            meetingURL: meetingURL
        )
    }

    nonisolated static func hasDocumentIndicator(
        eventURL: URL?,
        notes: String?,
        meetingURL: URL?
    ) -> Bool {
        var candidates: [URL] = []

        if let eventURL {
            candidates.append(eventURL)
        }

        if let notes = AlertCalendarString.trimmedNonEmpty(notes) {
            candidates.append(contentsOf: MeetingURLResolver.allURLs(in: notes))
        }

        return candidates.contains { candidate in
            guard !urlsMatch(candidate, meetingURL) else { return false }
            guard !MeetingURLResolver.isKnownMeetingURL(candidate) else { return false }
            return isDocumentIndicatorURL(candidate)
        }
    }

    nonisolated static func calendarItemURLMetadata(
        eventURL: URL?,
        notes: String?,
        meetingURL: URL?
    ) -> (count: Int, hosts: [String]) {
        let candidates = calendarItemURLs(
            eventURL: eventURL,
            notes: notes,
            meetingURL: meetingURL
        )

        var seenURLs: Set<String> = []
        var hosts: Set<String> = []
        for candidate in candidates where seenURLs.insert(normalizedURLString(candidate)).inserted {
            if candidate.isFileURL {
                hosts.insert("local-file")
            } else if let host = candidate.host?.lowercased() {
                hosts.insert(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
            }
        }

        return (seenURLs.count, hosts.sorted())
    }

    nonisolated static func agendaSummaryURLCandidates(
        eventURL: URL?,
        notes: String?,
        meetingURL: URL?
    ) -> [URL] {
        Array(calendarItemURLs(eventURL: eventURL, notes: notes, meetingURL: meetingURL)
            .filter { candidate in
                !candidate.isFileURL
                    && !urlsMatch(candidate, meetingURL)
                    && !MeetingURLResolver.isKnownMeetingURL(candidate)
                    && candidate.scheme?.lowercased() == "https"
            }
            .prefix(8))
    }

    nonisolated private static func calendarItemURLs(
        eventURL: URL?,
        notes: String?,
        meetingURL: URL?
    ) -> [URL] {
        var candidates = [eventURL, meetingURL].compactMap { $0 }
        if let notes = AlertCalendarString.trimmedNonEmpty(notes) {
            candidates.append(contentsOf: MeetingURLResolver.allURLs(in: notes))
        }

        var seenURLs: Set<String> = []
        return candidates.filter { candidate in
            seenURLs.insert(normalizedURLString(candidate)).inserted
        }
    }

    nonisolated static func isDocumentIndicatorURL(_ url: URL) -> Bool {
        if url.isFileURL {
            return true
        }

        let pathExtension = url.pathExtension.lowercased()
        if documentIndicatorPathExtensions.contains(pathExtension) {
            return true
        }

        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()

        if host == "docs.google.com" || host.hasSuffix(".docs.google.com") {
            return path.hasPrefix("/document/")
                || path.hasPrefix("/spreadsheets/")
                || path.hasPrefix("/presentation/")
                || path.hasPrefix("/drawings/")
                || path.hasPrefix("/forms/")
        }

        if host == "drive.google.com" || host.hasSuffix(".drive.google.com") {
            return path.hasPrefix("/file/")
        }

        if host == "1drv.ms" || host.hasSuffix(".1drv.ms") {
            return true
        }

        if host.hasSuffix(".sharepoint.com") || host == "sharepoint.com" {
            return pathExtension.isEmpty == false
        }

        return false
    }

    nonisolated private static var documentIndicatorPathExtensions: Set<String> {
        [
            "csv",
            "doc",
            "docx",
            "ics",
            "key",
            "numbers",
            "pages",
            "pdf",
            "ppt",
            "pptx",
            "rtf",
            "txt",
            "xls",
            "xlsx",
            "zip",
        ]
    }

    nonisolated static func urlsMatch(_ left: URL, _ right: URL?) -> Bool {
        guard let right else { return false }
        return normalizedURLString(left) == normalizedURLString(right)
    }

    nonisolated private static func normalizedURLString(_ url: URL) -> String {
        let rawString = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        return rawString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
