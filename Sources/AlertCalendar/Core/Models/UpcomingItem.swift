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
        self.gameStore = gameStore
        self.footballMatch = footballMatch
        self.footballMenuBarDisplay = footballMenuBarDisplay
    }

    var notificationKey: String {
        "\(id)|\(Int(date.timeIntervalSince1970))|\(kind.rawValue)|\(isAllDay)"
    }
}
