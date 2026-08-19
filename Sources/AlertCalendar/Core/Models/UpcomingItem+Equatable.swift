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
            && lhs.locationCoordinate == rhs.locationCoordinate
            && lhs.meetingURL == rhs.meetingURL
            && lhs.urlCount == rhs.urlCount
            && lhs.urlHosts == rhs.urlHosts
            && lhs.agendaSummaryURLCandidates == rhs.agendaSummaryURLCandidates
            && lhs.organizer == rhs.organizer
            && lhs.attendees == rhs.attendees
            && lhs.eventParticipationStatus == rhs.eventParticipationStatus
            && lhs.isRecurring == rhs.isRecurring
            && lhs.hasDocumentIndicator == rhs.hasDocumentIndicator
            && lhs.descriptionText == rhs.descriptionText
            && lhs.calendarID == rhs.calendarID
            && lhs.calendarName == rhs.calendarName
            && lhs.calendarColor == rhs.calendarColor
            && lhs.kind == rhs.kind
            && lhs.gameStore == rhs.gameStore
            && lhs.footballMatch == rhs.footballMatch
            && lhs.footballMenuBarDisplay == rhs.footballMenuBarDisplay
    }
}
