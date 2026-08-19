import Foundation

struct UpcomingItem: Identifiable, Equatable {
    let id: String
    let title: String
    let date: Date
    let endDate: Date?
    let isAllDay: Bool
    let showsMutedBackground: Bool
    let travelTimeMinutes: Int?
    let locationText: String?
    let locationCoordinate: ResolvedLocationCoordinate?
    let meetingURL: URL?
    let urlCount: Int
    let urlHosts: [String]
    let agendaSummaryURLCandidates: [URL]
    let organizer: MeetingOrganizer?
    let attendees: [MeetingAttendee]
    let eventParticipationStatus: EventParticipationStatus?
    let isRecurring: Bool
    let hasDocumentIndicator: Bool
    let descriptionText: String?
    let calendarID: String?
    let calendarName: String
    let calendarColor: AlertCalendarColor
    let kind: CalendarItemKind
    let gameStore: GameStore?
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
        locationCoordinate: ResolvedLocationCoordinate? = nil,
        meetingURL: URL?,
        urlCount: Int? = nil,
        urlHosts: [String] = [],
        agendaSummaryURLCandidates: [URL] = [],
        organizer: MeetingOrganizer? = nil,
        attendees: [MeetingAttendee] = [],
        eventParticipationStatus: EventParticipationStatus? = nil,
        isRecurring: Bool = false,
        hasDocumentIndicator: Bool = false,
        descriptionText: String? = nil,
        calendarID: String?,
        calendarName: String,
        calendarColor: AlertCalendarColor,
        kind: CalendarItemKind,
        gameStore: GameStore? = nil,
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
        self.locationCoordinate = locationCoordinate
        self.meetingURL = meetingURL
        self.urlCount = max(0, urlCount ?? (meetingURL == nil ? 0 : 1))
        self.urlHosts = Array(
            Set(
                (urlHosts + [meetingURL?.host].compactMap { $0 })
                    .compactMap { AlertCalendarString.trimmedNonEmpty($0) }
                    .map { $0.lowercased() }
                    .map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
            )
        ).sorted()
        self.agendaSummaryURLCandidates = agendaSummaryURLCandidates
        self.organizer = organizer
        self.attendees = attendees
        self.eventParticipationStatus = eventParticipationStatus
        self.isRecurring = isRecurring
        self.hasDocumentIndicator = hasDocumentIndicator
        self.descriptionText = descriptionText
        self.calendarID = calendarID
        self.calendarName = calendarName
        self.calendarColor = calendarColor
        self.kind = kind
        self.gameStore = gameStore
        self.footballMatch = footballMatch
        self.footballMenuBarDisplay = footballMenuBarDisplay
    }

    var notificationKey: String {
        "\(id)|\(Int(date.timeIntervalSince1970))|\(kind.rawValue)|\(isAllDay)"
    }
}
