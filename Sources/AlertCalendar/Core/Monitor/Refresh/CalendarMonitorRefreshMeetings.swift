import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    func normalizedTravelTimeMinutes(for event: EKEvent, meetingURL: URL?, locationText: String?) -> Int? {
        if managedFootballReference(for: event) != nil {
            return nil
        }

        // Virtual meetings should not be treated as trips to a physical place.
        if meetingURL != nil || isVirtualLocationText(locationText) {
            return nil
        }

        let hasLocationContext = event.structuredLocation != nil || normalizedLocation(for: event.location) != nil
        guard hasLocationContext else { return nil }

        // Prefer native travel time when available through Objective-C runtime.
        if let raw = (event as NSObject).value(forKey: "travelTime") as? NSNumber {
            let seconds = max(0, raw.doubleValue)
            if seconds >= 60 {
                return max(1, Int(ceil(seconds / 60.0)))
            }
        } else if let raw = (event as NSObject).value(forKey: "travelTime") as? Double, raw >= 60 {
            return max(1, Int(ceil(raw / 60.0)))
        }

        guard let alarms = event.alarms, !alarms.isEmpty else { return nil }

        let travelOffsets = alarms.compactMap { alarm -> TimeInterval? in
            let offset = alarm.relativeOffset
            guard offset < 0 else { return nil }
            let seconds = abs(offset)
            guard seconds >= 5 * 60, seconds <= 12 * 3600 else { return nil }
            return seconds
        }

        guard let seconds = travelOffsets.max() else { return nil }
        return max(1, Int(ceil(seconds / 60.0)))
    }

    func isVirtualLocationText(_ rawText: String?) -> Bool {
        guard let text = AlertCalendarString.trimmedNonEmpty(rawText) else { return false }
        let normalized = text.lowercased()

        let virtualKeywords = [
            "zoom",
            "google meet",
            "meet.google",
            "microsoft teams",
            "teams",
            "webex",
            "whereby",
            "jitsi",
            "chime",
            "virtual",
            "online",
            "video call",
            "videollamada",
        ]

        if virtualKeywords.contains(where: { normalized.contains($0) }) {
            return true
        }

        return allURLs(in: text).contains(where: isKnownMeetingURL)
    }

    func meetingURL(for event: EKEvent) -> URL? {
        var candidates: [URL] = []
        if let url = event.url {
            candidates.append(url)
        }
        if let notes = event.notes {
            candidates.append(contentsOf: allURLs(in: notes))
        }
        if let location = event.location {
            candidates.append(contentsOf: allURLs(in: location))
        }

        return MeetingURLResolver.bestMeetingURL(from: candidates)
    }

    func organizer(for event: EKEvent) -> MeetingOrganizer? {
        guard let organizer = event.organizer else { return nil }
        let emailAddress = attendeeEmailAddress(for: organizer)
        guard let displayText = participantDisplayText(name: organizer.name, emailAddress: emailAddress) else {
            return nil
        }

        return MeetingOrganizer(
            displayText: displayText,
            emailAddress: emailAddress
        )
    }

    func invitees(for event: EKEvent) -> [MeetingAttendee] {
        let rawInvitees = (event.attendees ?? []).compactMap { participant -> MeetingAttendee? in
            guard !participant.isCurrentUser else { return nil }

            let emailAddress = attendeeEmailAddress(for: participant)
            guard let displayText = participantDisplayText(name: participant.name, emailAddress: emailAddress) else {
                return nil
            }

            let identifier = emailAddress ?? displayText
            guard AlertCalendarString.trimmedNonEmpty(identifier) != nil else { return nil }

            return MeetingAttendee(
                id: identifier,
                displayText: displayText,
                emailAddress: emailAddress,
                response: attendeeResponse(for: participant)
            )
        }

        return MeetingAttendee.normalized(rawInvitees)
    }

    private func attendeeResponse(for participant: EKParticipant) -> MeetingAttendeeResponse {
        switch participant.participantStatus {
        case .accepted:
            return .accepted
        case .tentative:
            return .tentative
        case .declined:
            return .declined
        case .pending, .unknown, .delegated, .completed, .inProcess:
            return .pending
        @unknown default:
            return .pending
        }
    }

    private func participantDisplayText(name: String?, emailAddress: String?) -> String? {
        if let name = AlertCalendarString.trimmedNonEmpty(name) {
            return name
        }

        return AlertCalendarString.trimmedNonEmpty(emailAddress)
    }

    private func attendeeEmailAddress(for participant: EKParticipant) -> String? {
        let participantURL = participant.url
        var candidate = participantURL.absoluteString
        candidate = AlertCalendarString.trimmedNonEmpty(candidate.removingPercentEncoding ?? candidate) ?? ""

        if candidate.lowercased().hasPrefix("mailto:") {
            candidate.removeFirst("mailto:".count)
        }

        guard candidate.contains("@") else { return nil }
        return MeetingAttendee.normalizedEmailAddress(candidate)
    }

    func allURLs(in text: String) -> [URL] {
        MeetingURLResolver.allURLs(in: text)
    }

    func isKnownMeetingURL(_ url: URL) -> Bool {
        MeetingURLResolver.isKnownMeetingURL(url)
    }
}
