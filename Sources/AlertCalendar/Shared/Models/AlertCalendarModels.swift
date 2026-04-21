import AppKit
import Foundation

enum CalendarItemKind: String {
    case event = "Event"
    case reminder = "Reminder"
}

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

    var statusColor: NSColor {
        switch self {
        case .accepted:
            return .systemGreen
        case .tentative:
            return .systemOrange
        case .declined:
            return .systemRed
        case .pending:
            return .tertiaryLabelColor
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

    fileprivate func preferredDuplicateStatus(comparedTo candidate: MeetingAttendeeResponse) -> MeetingAttendeeResponse {
        if duplicateResolutionPriority != candidate.duplicateResolutionPriority {
            return duplicateResolutionPriority < candidate.duplicateResolutionPriority ? self : candidate
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

    func applyingContact(displayText: String?, avatarImageData: Data?) -> MeetingOrganizer {
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

    func applyingContact(displayText: String?, avatarImageData: Data?) -> MeetingAttendee {
        MeetingAttendee(
            id: id,
            displayText: displayText ?? self.displayText,
            emailAddress: emailAddress,
            response: response,
            avatarImageData: avatarImageData ?? self.avatarImageData
        )
    }

    static func normalized(_ attendees: [MeetingAttendee]) -> [MeetingAttendee] {
        var attendeesByID: [String: MeetingAttendee] = [:]
        attendeesByID.reserveCapacity(attendees.count)

        for attendee in attendees {
            let trimmedDisplayText = attendee.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDisplayText.isEmpty else { continue }

            let normalizedEmailAddress = attendee.emailAddress?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let normalizedID = attendee.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let resolvedID = normalizedEmailAddress ?? normalizedID
            guard !resolvedID.isEmpty else { continue }

            let normalizedAttendee = MeetingAttendee(
                id: resolvedID,
                displayText: trimmedDisplayText,
                emailAddress: normalizedEmailAddress,
                response: attendee.response,
                avatarImageData: attendee.avatarImageData
            )

            if let existing = attendeesByID[resolvedID] {
                attendeesByID[resolvedID] = merged(existing: existing, candidate: normalizedAttendee)
            } else {
                attendeesByID[resolvedID] = normalizedAttendee
            }
        }

        return attendeesByID.values.sorted { left, right in
            if left.response.sortPriority != right.response.sortPriority {
                return left.response.sortPriority < right.response.sortPriority
            }

            let titleOrder = left.displayText.localizedCaseInsensitiveCompare(right.displayText)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }

            return left.id < right.id
        }
    }

    private static func merged(existing: MeetingAttendee, candidate: MeetingAttendee) -> MeetingAttendee {
        let preferredStatus = existing.response.preferredDuplicateStatus(comparedTo: candidate.response)
        let preferredAttendee = preferredDisplayAttendee(existing: existing, candidate: candidate)

        return MeetingAttendee(
            id: existing.id,
            displayText: preferredAttendee.displayText,
            emailAddress: preferredAttendee.emailAddress ?? existing.emailAddress ?? candidate.emailAddress,
            response: preferredStatus,
            avatarImageData: preferredAttendee.avatarImageData ?? existing.avatarImageData ?? candidate.avatarImageData
        )
    }

    private static func preferredDisplayAttendee(existing: MeetingAttendee, candidate: MeetingAttendee) -> MeetingAttendee {
        let existingLooksLikeEmail = looksLikeEmail(existing.displayText)
        let candidateLooksLikeEmail = looksLikeEmail(candidate.displayText)

        if existingLooksLikeEmail != candidateLooksLikeEmail {
            return existingLooksLikeEmail ? candidate : existing
        }

        if existing.displayText.count != candidate.displayText.count {
            return existing.displayText.count >= candidate.displayText.count ? existing : candidate
        }

        return existing
    }

    private static func looksLikeEmail(_ text: String) -> Bool {
        text.contains("@")
    }
}

struct UpcomingItem: Identifiable, Equatable {
    let id: String
    let title: String
    let date: Date
    let endDate: Date?
    let isAllDay: Bool
    let showsMutedBackground: Bool
    let travelTimeMinutes: Int?
    let locationText: String?
    let meetingURL: URL?
    let organizer: MeetingOrganizer?
    let attendees: [MeetingAttendee]
    let calendarID: String?
    let calendarName: String
    let calendarColor: NSColor
    let kind: CalendarItemKind
    let footballMatch: FootballFixtureMatch?
    let footballMenuBarDisplay: FootballMenuBarDisplay?

    init(
        id: String,
        title: String,
        date: Date,
        endDate: Date?,
        isAllDay: Bool,
        showsMutedBackground: Bool,
        travelTimeMinutes: Int?,
        locationText: String?,
        meetingURL: URL?,
        organizer: MeetingOrganizer? = nil,
        attendees: [MeetingAttendee] = [],
        calendarID: String?,
        calendarName: String,
        calendarColor: NSColor,
        kind: CalendarItemKind,
        footballMatch: FootballFixtureMatch?,
        footballMenuBarDisplay: FootballMenuBarDisplay?
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.showsMutedBackground = showsMutedBackground
        self.travelTimeMinutes = travelTimeMinutes
        self.locationText = locationText
        self.meetingURL = meetingURL
        self.organizer = organizer
        self.attendees = attendees
        self.calendarID = calendarID
        self.calendarName = calendarName
        self.calendarColor = calendarColor
        self.kind = kind
        self.footballMatch = footballMatch
        self.footballMenuBarDisplay = footballMenuBarDisplay
    }

    var notificationKey: String {
        "\(id)|\(Int(date.timeIntervalSince1970))|\(kind.rawValue)|\(isAllDay)"
    }
}

enum ActiveEventDisplayMode: String, CaseIterable, Identifiable {
    case remaining
    case elapsed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remaining:
            return "Show time remaining"
        case .elapsed:
            return "Show elapsed time"
        }
    }
}

struct AvailableCalendar: Identifiable, Equatable {
    let id: String
    let title: String
    let color: NSColor
    let kind: CalendarItemKind
    let accountTitle: String
    let isSubscribed: Bool
}

enum MenuMarkerStyle: Equatable {
    case color(NSColor)
    case reminder(NSColor)
    case birthday(NSColor)
    case allDay(NSColor)
    case sunrise
    case solarNoon
    case sunset
    case solarMidnight
    case perihelion
    case aphelion
    case marchEquinox
    case juneSolstice
    case septemberEquinox
    case decemberSolstice
    case newMoon
    case waxingCrescent
    case firstQuarter
    case waxingGibbous
    case fullMoon
    case waningGibbous
    case lastQuarter
    case waningCrescent

    static func == (lhs: MenuMarkerStyle, rhs: MenuMarkerStyle) -> Bool {
        switch (lhs, rhs) {
        case let (.color(left), .color(right)):
            return left.isEqual(right)
        case let (.reminder(left), .reminder(right)):
            return left.isEqual(right)
        case let (.birthday(left), .birthday(right)):
            return left.isEqual(right)
        case let (.allDay(left), .allDay(right)):
            return left.isEqual(right)
        case (.sunrise, .sunrise),
            (.solarNoon, .solarNoon),
            (.sunset, .sunset),
            (.solarMidnight, .solarMidnight),
            (.perihelion, .perihelion),
            (.aphelion, .aphelion),
            (.marchEquinox, .marchEquinox),
            (.juneSolstice, .juneSolstice),
            (.septemberEquinox, .septemberEquinox),
            (.decemberSolstice, .decemberSolstice),
            (.newMoon, .newMoon),
            (.waxingCrescent, .waxingCrescent),
            (.firstQuarter, .firstQuarter),
            (.waxingGibbous, .waxingGibbous),
            (.fullMoon, .fullMoon),
            (.waningGibbous, .waningGibbous),
            (.lastQuarter, .lastQuarter),
            (.waningCrescent, .waningCrescent):
            return true
        default:
            return false
        }
    }
}

extension UpcomingItem {
    static func == (lhs: UpcomingItem, rhs: UpcomingItem) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.date == rhs.date
            && lhs.endDate == rhs.endDate
            && lhs.isAllDay == rhs.isAllDay
            && lhs.showsMutedBackground == rhs.showsMutedBackground
            && lhs.travelTimeMinutes == rhs.travelTimeMinutes
            && lhs.locationText == rhs.locationText
            && lhs.meetingURL == rhs.meetingURL
            && lhs.organizer == rhs.organizer
            && lhs.attendees == rhs.attendees
            && lhs.calendarID == rhs.calendarID
            && lhs.calendarName == rhs.calendarName
            && colorsAreEqual(lhs.calendarColor, rhs.calendarColor)
            && lhs.kind == rhs.kind
            && lhs.footballMatch == rhs.footballMatch
            && lhs.footballMenuBarDisplay == rhs.footballMenuBarDisplay
    }
}

extension AvailableCalendar {
    static func == (lhs: AvailableCalendar, rhs: AvailableCalendar) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && colorsAreEqual(lhs.color, rhs.color)
            && lhs.kind == rhs.kind
            && lhs.accountTitle == rhs.accountTitle
            && lhs.isSubscribed == rhs.isSubscribed
    }
}

private func colorsAreEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
    lhs.isEqual(rhs)
}

private func meetingParticipantAvatarFallbackText(
    displayText: String,
    emailAddress: String?
) -> String {
    let trimmedDisplayText = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    if let firstCharacter = trimmedDisplayText.first {
        return String(firstCharacter).uppercased()
    }

    let trimmedEmailAddress = emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if let firstCharacter = trimmedEmailAddress.first {
        return String(firstCharacter).uppercased()
    }

    return "?"
}
