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

        if let nativeTravelTimeMinutes = EventTravelTimeResolver.travelTimeMinutes(for: event) {
            return nativeTravelTimeMinutes
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
        if let cached = virtualLocationTextCache.value(forKey: normalized) {
            return cached
        }

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
            virtualLocationTextCache.insert(true, forKey: normalized)
            return true
        }

        guard MeetingURLResolver.shouldInspectTextForURLs(text) else {
            virtualLocationTextCache.insert(false, forKey: normalized)
            return false
        }

        let result = allURLs(in: text).contains(where: isKnownMeetingURL)
        virtualLocationTextCache.insert(result, forKey: normalized)
        return result
    }

    func meetingURL(for event: EKEvent) -> URL? {
        EventMeetingURLResolver.meetingURL(for: event)
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
        let organizerEmailAddress = event.organizer.flatMap { attendeeEmailAddress(for: $0) }
        let organizerDisplayText = event.organizer.flatMap { organizer in
            participantDisplayText(name: organizer.name, emailAddress: organizerEmailAddress)
        }

        let rawInvitees = (event.attendees ?? []).compactMap { participant -> MeetingAttendee? in
            let emailAddress = attendeeEmailAddress(for: participant)
            guard let displayText = participantDisplayText(name: participant.name, emailAddress: emailAddress) else {
                return nil
            }
            guard Self.shouldIncludeInvitee(
                isCurrentUser: participant.isCurrentUser,
                participantEmailAddress: emailAddress,
                participantDisplayText: displayText,
                organizerEmailAddress: organizerEmailAddress,
                organizerDisplayText: organizerDisplayText
            ) else {
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

    nonisolated static func shouldIncludeInvitee(
        isCurrentUser _: Bool,
        participantEmailAddress: String?,
        participantDisplayText: String?,
        organizerEmailAddress: String?,
        organizerDisplayText: String?
    ) -> Bool {
        !participantMatchesOrganizer(
            participantEmailAddress: participantEmailAddress,
            participantDisplayText: participantDisplayText,
            organizerEmailAddress: organizerEmailAddress,
            organizerDisplayText: organizerDisplayText
        )
    }

    nonisolated static func participantMatchesOrganizer(
        participantEmailAddress: String?,
        participantDisplayText: String?,
        organizerEmailAddress: String?,
        organizerDisplayText: String?
    ) -> Bool {
        let participantEmailAddress = MeetingAttendee.normalizedEmailAddress(participantEmailAddress)
        let organizerEmailAddress = MeetingAttendee.normalizedEmailAddress(organizerEmailAddress)
        if let participantEmailAddress,
           let organizerEmailAddress {
            return participantEmailAddress == organizerEmailAddress
        }

        let participantDisplayText = MeetingAttendee.normalizedIdentity(participantDisplayText)
        let organizerDisplayText = MeetingAttendee.normalizedIdentity(organizerDisplayText)

        if let participantDisplayText,
           let organizerEmailAddress,
           participantDisplayText == organizerEmailAddress {
            return true
        }

        if let participantEmailAddress,
           let organizerDisplayText,
           participantEmailAddress == organizerDisplayText {
            return true
        }

        if let participantDisplayText,
           let organizerDisplayText,
           participantDisplayText == organizerDisplayText {
            return true
        }

        return false
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
