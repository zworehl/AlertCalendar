import Foundation

enum CalendarItemKind: String {
    case event = "Event"
    case reminder = "Reminder"
}

enum EventParticipationStatus: String, Equatable {
    case accepted
    case tentative
    case pending
    case declined

    var usesTexturedFill: Bool {
        switch self {
        case .accepted:
            return false
        case .tentative, .pending, .declined:
            return true
        }
    }

    var appleCalendarBackgroundAlpha: CGFloat {
        switch self {
        case .accepted:
            return 0.30
        case .tentative:
            return 0.30
        case .pending:
            return 0.24
        case .declined:
            return 0.20
        }
    }

    var appleCalendarTextAlpha: CGFloat {
        switch self {
        case .accepted:
            return 1.0
        case .tentative:
            return 0.88
        case .pending:
            return 0.74
        case .declined:
            return 0.62
        }
    }

    var appleCalendarStripeAlpha: CGFloat {
        switch self {
        case .accepted:
            return 0
        case .tentative:
            return 0.16
        case .pending:
            return 0.18
        case .declined:
            return 0.24
        }
    }

    var appleCalendarStripeSpacing: CGFloat {
        switch self {
        case .accepted:
            return 6
        case .tentative:
            return 6
        case .pending:
            return 7
        case .declined:
            return 5
        }
    }
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

    static func normalizedEmailAddress(_ emailAddress: String?) -> String? {
        normalizedIdentity(emailAddress)
    }

    static func normalizedIdentity(_ value: String?) -> String? {
        AlertCalendarString.trimmedNonEmpty(value)?.lowercased()
    }

    static func normalized(_ attendees: [MeetingAttendee]) -> [MeetingAttendee] {
        var attendeesByID: [String: MeetingAttendee] = [:]
        attendeesByID.reserveCapacity(attendees.count)

        for attendee in attendees {
            guard let trimmedDisplayText = AlertCalendarString.trimmedNonEmpty(attendee.displayText) else {
                continue
            }

            let normalizedEmailAddress = normalizedEmailAddress(attendee.emailAddress)
            let normalizedID = normalizedIdentity(attendee.id)
            guard let resolvedID = normalizedEmailAddress ?? normalizedID else { continue }

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
    let eventParticipationStatus: EventParticipationStatus?
    let isRecurring: Bool
    let hasDocumentIndicator: Bool
    let calendarID: String?
    let calendarName: String
    let calendarColor: AlertCalendarColor
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
        eventParticipationStatus: EventParticipationStatus? = nil,
        isRecurring: Bool = false,
        hasDocumentIndicator: Bool = false,
        calendarID: String?,
        calendarName: String,
        calendarColor: AlertCalendarColor,
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
        self.eventParticipationStatus = eventParticipationStatus
        self.isRecurring = isRecurring
        self.hasDocumentIndicator = hasDocumentIndicator
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
    let color: AlertCalendarColor
    let kind: CalendarItemKind
    let accountTitle: String
    let isSubscribed: Bool
}

enum MenuMarkerStyle: Equatable {
    case color(AlertCalendarColor)
    case reminder(AlertCalendarColor)
    case birthday(AlertCalendarColor)
    case allDay(AlertCalendarColor)
    case travel(AlertCalendarColor)
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
            return left == right
        case let (.reminder(left), .reminder(right)):
            return left == right
        case let (.birthday(left), .birthday(right)):
            return left == right
        case let (.allDay(left), .allDay(right)):
            return left == right
        case let (.travel(left), .travel(right)):
            return left == right
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
            && lhs.eventParticipationStatus == rhs.eventParticipationStatus
            && lhs.isRecurring == rhs.isRecurring
            && lhs.hasDocumentIndicator == rhs.hasDocumentIndicator
            && lhs.calendarID == rhs.calendarID
            && lhs.calendarName == rhs.calendarName
            && lhs.calendarColor == rhs.calendarColor
            && lhs.kind == rhs.kind
            && lhs.footballMatch == rhs.footballMatch
            && lhs.footballMenuBarDisplay == rhs.footballMenuBarDisplay
    }
}

extension AvailableCalendar {
    static func == (lhs: AvailableCalendar, rhs: AvailableCalendar) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.color == rhs.color
            && lhs.kind == rhs.kind
            && lhs.accountTitle == rhs.accountTitle
            && lhs.isSubscribed == rhs.isSubscribed
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
