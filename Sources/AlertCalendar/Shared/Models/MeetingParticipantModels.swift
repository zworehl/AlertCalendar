import Foundation

enum MeetingAttendeeResponse: String, Equatable {
    case accepted
    case tentative
    case declined
    case pending

    var statusSymbolName: String {
        switch self {
        case .accepted:
            return "checkmark.circle"
        case .tentative, .pending:
            return "questionmark.circle"
        case .declined:
            return "xmark.circle"
        }
    }

    var statusColor: AlertCalendarColor {
        switch self {
        case .accepted:
            return .systemGreen
        case .tentative:
            return .systemOrange
        case .declined:
            return .systemRed
        case .pending:
            return .tertiaryLabel
        }
    }

    fileprivate var sortPriority: Int {
        switch self {
        case .accepted:
            return 0
        case .tentative:
            return 1
        case .declined:
            return 2
        case .pending:
            return 3
        }
    }

    fileprivate var duplicateResolutionPriority: Int {
        switch self {
        case .accepted, .tentative, .declined:
            return 0
        case .pending:
            return 1
        }
    }

    fileprivate func preferredDuplicateStatus(
        comparedTo candidate: MeetingAttendeeResponse
    ) -> MeetingAttendeeResponse {
        if duplicateResolutionPriority != candidate.duplicateResolutionPriority {
            return duplicateResolutionPriority < candidate.duplicateResolutionPriority
                ? self
                : candidate
        }

        return self
    }
}

struct MeetingOrganizer: Equatable {
    let displayText: String
    let emailAddress: String?
    let avatarImageData: Data?

    init(
        displayText: String,
        emailAddress: String?,
        avatarImageData: Data? = nil
    ) {
        self.displayText = displayText
        self.emailAddress = emailAddress
        self.avatarImageData = avatarImageData
    }

    var avatarFallbackText: String {
        meetingParticipantAvatarFallbackText(
            displayText: displayText,
            emailAddress: emailAddress
        )
    }

    func applyingContact(
        displayText: String?,
        avatarImageData: Data?
    ) -> MeetingOrganizer {
        MeetingOrganizer(
            displayText: displayText ?? self.displayText,
            emailAddress: emailAddress,
            avatarImageData: avatarImageData ?? self.avatarImageData
        )
    }
}

struct MeetingAttendee: Identifiable, Equatable {
    let id: String
    let displayText: String
    let emailAddress: String?
    let response: MeetingAttendeeResponse
    let avatarImageData: Data?

    init(
        id: String,
        displayText: String,
        emailAddress: String?,
        response: MeetingAttendeeResponse,
        avatarImageData: Data? = nil
    ) {
        self.id = id
        self.displayText = displayText
        self.emailAddress = emailAddress
        self.response = response
        self.avatarImageData = avatarImageData
    }

    var avatarFallbackText: String {
        meetingParticipantAvatarFallbackText(
            displayText: displayText,
            emailAddress: emailAddress
        )
    }

    func applyingContact(
        displayText: String?,
        avatarImageData: Data?
    ) -> MeetingAttendee {
        MeetingAttendee(
            id: id,
            displayText: displayText ?? self.displayText,
            emailAddress: emailAddress,
            response: response,
            avatarImageData: avatarImageData ?? self.avatarImageData
        )
    }

    static func normalizedEmailAddress(_ emailAddress: String?) -> String? {
        normalizedIdentity(emailAddress)
    }

    static func normalizedIdentity(_ value: String?) -> String? {
        AlertCalendarString.trimmedNonEmpty(value)?.lowercased()
    }

    static func normalized(_ attendees: [MeetingAttendee]) -> [MeetingAttendee] {
        var normalizedAttendees: [MeetingAttendee] = []
        normalizedAttendees.reserveCapacity(attendees.count)

        for attendee in attendees {
            guard let trimmedDisplayText = AlertCalendarString.trimmedNonEmpty(
                attendee.displayText
            ) else {
                continue
            }

            let normalizedEmailAddress = normalizedEmailAddress(attendee.emailAddress)
            let normalizedID = normalizedIdentity(attendee.id)
            guard let resolvedID = normalizedEmailAddress ?? normalizedID else {
                continue
            }

            let normalizedAttendee = MeetingAttendee(
                id: resolvedID,
                displayText: trimmedDisplayText,
                emailAddress: normalizedEmailAddress,
                response: attendee.response,
                avatarImageData: attendee.avatarImageData
            )

            let duplicateIndexes = normalizedAttendees.indices.filter { index in
                representsSameParticipant(
                    normalizedAttendees[index],
                    normalizedAttendee
                )
            }

            guard !duplicateIndexes.isEmpty else {
                normalizedAttendees.append(normalizedAttendee)
                continue
            }

            var mergedAttendee = normalizedAttendee
            for index in duplicateIndexes.reversed() {
                mergedAttendee = merged(
                    existing: normalizedAttendees.remove(at: index),
                    candidate: mergedAttendee
                )
            }
            normalizedAttendees.append(mergedAttendee)
        }

        return normalizedAttendees.sorted { left, right in
            if left.response.sortPriority != right.response.sortPriority {
                return left.response.sortPriority < right.response.sortPriority
            }

            let titleOrder = left.displayText.localizedCaseInsensitiveCompare(
                right.displayText
            )
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }

            return left.id < right.id
        }
    }

    private static func representsSameParticipant(
        _ left: MeetingAttendee,
        _ right: MeetingAttendee
    ) -> Bool {
        if let leftEmailAddress = normalizedEmailAddress(left.emailAddress),
           let rightEmailAddress = normalizedEmailAddress(right.emailAddress),
           leftEmailAddress == rightEmailAddress {
            return true
        }

        if let leftID = normalizedIdentity(left.id),
           let rightID = normalizedIdentity(right.id),
           leftID == rightID {
            return true
        }

        guard let leftDisplayText = normalizedIdentity(left.displayText),
              let rightDisplayText = normalizedIdentity(right.displayText) else {
            return false
        }

        return leftDisplayText == rightDisplayText
    }

    private static func merged(
        existing: MeetingAttendee,
        candidate: MeetingAttendee
    ) -> MeetingAttendee {
        let preferredStatus = existing.response.preferredDuplicateStatus(
            comparedTo: candidate.response
        )
        let preferredAttendee = preferredDisplayAttendee(
            existing: existing,
            candidate: candidate
        )
        let resolvedEmailAddress = preferredAttendee.emailAddress
            ?? existing.emailAddress
            ?? candidate.emailAddress

        return MeetingAttendee(
            id: resolvedEmailAddress ?? existing.id,
            displayText: preferredAttendee.displayText,
            emailAddress: resolvedEmailAddress,
            response: preferredStatus,
            avatarImageData: preferredAttendee.avatarImageData
                ?? existing.avatarImageData
                ?? candidate.avatarImageData
        )
    }

    private static func preferredDisplayAttendee(
        existing: MeetingAttendee,
        candidate: MeetingAttendee
    ) -> MeetingAttendee {
        let existingLooksLikeEmail = looksLikeEmail(existing.displayText)
        let candidateLooksLikeEmail = looksLikeEmail(candidate.displayText)

        if existingLooksLikeEmail != candidateLooksLikeEmail {
            return existingLooksLikeEmail ? candidate : existing
        }

        if existing.displayText.count != candidate.displayText.count {
            return existing.displayText.count >= candidate.displayText.count
                ? existing
                : candidate
        }

        return existing
    }

    private static func looksLikeEmail(_ text: String) -> Bool {
        text.contains("@")
    }
}

private func meetingParticipantAvatarFallbackText(
    displayText: String,
    emailAddress: String?
) -> String {
    if let firstCharacter = AlertCalendarString.trimmedNonEmpty(displayText)?.first {
        return String(firstCharacter).uppercased()
    }

    if let firstCharacter = AlertCalendarString.trimmedNonEmpty(emailAddress)?.first {
        return String(firstCharacter).uppercased()
    }

    return "?"
}
