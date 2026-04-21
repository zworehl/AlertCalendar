import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    func loadEvents(
        from start: Date,
        to end: Date,
        now: Date,
        calendars: [EKCalendar]
    ) -> (timedItems: [UpcomingItem], allDayItems: [UpcomingItem]) {
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        var timedItems: [UpcomingItem] = []
        var allDayItems: [UpcomingItem] = []

        for event in eventStore.events(matching: predicate) {
            guard let startDate = event.startDate else { continue }
            let calendarIdentifier = event.calendar.calendarIdentifier
            let eventEnd = event.endDate ?? Calendar.current.date(
                byAdding: .hour,
                value: 1,
                to: startDate
            ) ?? startDate
            let identifier = event.eventIdentifier ?? UUID().uuidString
            let footballMatch = footballMatch(for: event)
            let title = normalizedTitle(event.title)
            let calendarName = event.calendar.title
            let calendarColor = color(from: event.calendar)
            let showsMutedBackground = requiresMutedParticipationStyle(for: event)
            let meetingURL = meetingURL(for: event)
            let locationText = Self.preferredLocationText(
                eventLocation: event.location,
                footballMatchLocation: footballMatch?.locationText
            )
            let footballMenuBarDisplay = footballMatch.map(footballMenuBarDisplay(for:))
            let organizer = organizer(for: event)
            let attendees = invitees(for: event)
            let travelTimeMinutes = normalizedTravelTimeMinutes(
                for: event,
                meetingURL: meetingURL,
                locationText: locationText
            )

            if event.isAllDay {
                let calendar = Calendar.current
                let todayStart = calendar.startOfDay(for: now)
                guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else { continue }
                let appliesToToday = startDate < tomorrowStart && eventEnd > todayStart
                guard appliesToToday else { continue }
                allDayItems.append(
                    UpcomingItem(
                        id: identifier,
                        title: title,
                        date: startDate,
                        endDate: event.endDate,
                        isAllDay: true,
                        showsMutedBackground: showsMutedBackground,
                        travelTimeMinutes: travelTimeMinutes,
                        locationText: locationText,
                        meetingURL: meetingURL,
                        organizer: organizer,
                        attendees: attendees,
                        calendarID: calendarIdentifier,
                        calendarName: calendarName,
                        calendarColor: calendarColor,
                        kind: .event,
                        footballMatch: footballMatch,
                        footballMenuBarDisplay: footballMenuBarDisplay
                    )
                )
                continue
            }

            let isUpcoming = startDate >= now
            let isActive = startDate <= now && eventEnd > now
            guard isUpcoming || isActive else { continue }

            timedItems.append(
                UpcomingItem(
                    id: identifier,
                    title: title,
                    date: startDate,
                    endDate: event.endDate,
                    isAllDay: false,
                    showsMutedBackground: showsMutedBackground,
                    travelTimeMinutes: travelTimeMinutes,
                    locationText: locationText,
                    meetingURL: meetingURL,
                    organizer: organizer,
                    attendees: attendees,
                    calendarID: calendarIdentifier,
                    calendarName: calendarName,
                    calendarColor: calendarColor,
                    kind: .event,
                    footballMatch: footballMatch,
                    footballMenuBarDisplay: footballMenuBarDisplay
                )
            )
        }

        timedItems.sort { $0.date < $1.date }
        allDayItems.sort { $0.date < $1.date }
        return (timedItems, allDayItems)
    }

    nonisolated static func preferredLocationText(eventLocation: String?, footballMatchLocation: String?) -> String? {
        if let footballLocation = normalizedLocationText(footballMatchLocation) {
            return footballLocation
        }

        return normalizedLocationText(eventLocation)
    }

    private nonisolated static func normalizedLocationText(_ rawLocation: String?) -> String? {
        guard let rawLocation else { return nil }
        let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func loadReminders(from start: Date?, to end: Date, calendars: [EKCalendar]) async -> [UpcomingItem] {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: start,
            ending: end,
            calendars: calendars
        )

        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        return reminders.compactMap { reminder -> UpcomingItem? in
            guard let dueDate = dueDate(for: reminder) else { return nil }
            guard reminderHasExplicitTime(reminder) else { return nil }
            return UpcomingItem(
                id: reminder.calendarItemIdentifier,
                title: normalizedTitle(reminder.title),
                date: dueDate,
                endDate: nil,
                isAllDay: false,
                showsMutedBackground: false,
                travelTimeMinutes: nil,
                locationText: nil,
                meetingURL: nil,
                organizer: nil,
                attendees: [],
                calendarID: reminder.calendar.calendarIdentifier,
                calendarName: reminder.calendar.title,
                calendarColor: color(from: reminder.calendar),
                kind: .reminder,
                footballMatch: nil,
                footballMenuBarDisplay: nil
            )
        }
    }

    func requiresMutedParticipationStyle(for event: EKEvent) -> Bool {
        if let participantStatus = event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus {
            switch participantStatus {
            case .accepted:
                return false
            case .tentative, .pending:
                return true
            default:
                return true
            }
        }

        return event.status == .tentative
    }

    func dueDate(for reminder: EKReminder) -> Date? {
        guard let components = reminder.dueDateComponents else { return nil }
        if let fromComponents = components.date {
            return fromComponents
        }
        return Calendar.current.date(from: components)
    }

    func reminderHasExplicitTime(_ reminder: EKReminder) -> Bool {
        guard let components = reminder.dueDateComponents else { return false }
        return components.hour != nil || components.minute != nil || components.second != nil
    }

    func normalizedLocation(for rawLocation: String?) -> String? {
        guard let rawLocation else { return nil }
        let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
