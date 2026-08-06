import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    nonisolated static func shouldIncludeAllDayItem(
        startDate: Date,
        endDate: Date?,
        now: Date,
        futureWindowEnd: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let todayStart = calendar.startOfDay(for: now)
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return false
        }

        let normalizedEndDate = endDate
            ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: startDate))
            ?? startDate
        let overlapsToday = startDate < tomorrowStart && normalizedEndDate > todayStart
        if overlapsToday {
            return true
        }

        return startDate >= now && startDate <= futureWindowEnd
    }

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
            let eventParticipationStatus = eventParticipationStatus(for: event)
            guard Self.shouldIncludeEvent(
                status: event.status,
                participationStatus: eventParticipationStatus
            ) else {
                continue
            }
            let showsMutedBackground = eventParticipationStatus?.usesTexturedFill == true
            let meetingURL = meetingURL(for: event)
            let locationText = Self.preferredLocationText(
                eventLocation: event.location,
                footballMatchLocation: footballMatch?.locationText
            )
            let footballMenuBarDisplay = footballMatch.map(footballMenuBarDisplay(for:))
            let gameStore = event.isAllDay ? event.url.flatMap(Self.gameStore(for:)) : nil
            let organizer = organizer(for: event)
            let attendees = invitees(for: event)
            let isRecurring = isRecurringEvent(event)
            let hasDocumentIndicator = hasDocumentIndicator(for: event, meetingURL: meetingURL)
            let travelTimeMinutes = normalizedTravelTimeMinutes(
                for: event,
                meetingURL: meetingURL,
                locationText: locationText
            )

            if event.isAllDay {
                guard Self.shouldIncludeAllDayItem(
                    startDate: startDate,
                    endDate: event.endDate ?? eventEnd,
                    now: now,
                    futureWindowEnd: end
                ) else { continue }
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
                        eventParticipationStatus: eventParticipationStatus,
                        isRecurring: isRecurring,
                        hasDocumentIndicator: hasDocumentIndicator,
                        calendarID: calendarIdentifier,
                        calendarName: calendarName,
                        calendarColor: calendarColor,
                        kind: .event,
                        gameStore: gameStore,
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
                    eventParticipationStatus: eventParticipationStatus,
                    isRecurring: isRecurring,
                    hasDocumentIndicator: hasDocumentIndicator,
                    calendarID: calendarIdentifier,
                    calendarName: calendarName,
                    calendarColor: calendarColor,
                    kind: .event,
                    gameStore: gameStore,
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
        AlertCalendarString.trimmedNonEmpty(rawLocation)
    }

    func loadReminders(from start: Date?, to end: Date, calendars: [EKCalendar]) async -> [UpcomingItem] {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: start,
            ending: end,
            calendars: calendars
        )

        let reminders = await fetchReminders(
            matching: predicate,
            timeout: CalendarMonitorCadence.reminderFetchTimeoutInterval
        )

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
                isRecurring: isRecurringReminder(reminder),
                calendarID: reminder.calendar.calendarIdentifier,
                calendarName: reminder.calendar.title,
                calendarColor: color(from: reminder.calendar),
                kind: .reminder,
                footballMatch: nil,
                footballMenuBarDisplay: nil
            )
        }
    }

    func fetchReminders(matching predicate: NSPredicate, timeout: TimeInterval) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            var didResume = false

            func resumeOnce(with reminders: [EKReminder], timedOut: Bool = false) {
                guard !didResume else { return }
                didResume = true
                if timedOut {
                    CalendarMonitorLog.refresh.error("Timed out fetching reminders from EventKit")
                }
                continuation.resume(returning: reminders)
            }

            eventStore.fetchReminders(matching: predicate) { reminders in
                DispatchQueue.main.async {
                    resumeOnce(with: reminders ?? [])
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                resumeOnce(with: [], timedOut: true)
            }
        }
    }

    nonisolated static func shouldIncludeEvent(
        status: EKEventStatus,
        participationStatus: EventParticipationStatus?
    ) -> Bool {
        switch status {
        case .canceled:
            return false
        case .none, .confirmed, .tentative:
            break
        @unknown default:
            break
        }

        return participationStatus != .declined
    }

    func eventParticipationStatus(for event: EKEvent) -> EventParticipationStatus? {
        if let participantStatus = event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus {
            return Self.eventParticipationStatus(for: participantStatus)
        }

        if event.status == .tentative || event.availability == .tentative {
            return .tentative
        }

        return nil
    }

    nonisolated static func eventParticipationStatus(for participantStatus: EKParticipantStatus) -> EventParticipationStatus {
        switch participantStatus {
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

    func isRecurringEvent(_ event: EKEvent) -> Bool {
        event.hasRecurrenceRules || event.isDetached
    }

    func isRecurringReminder(_ reminder: EKReminder) -> Bool {
        reminder.hasRecurrenceRules
    }

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
        AlertCalendarString.trimmedNonEmpty(rawLocation)
    }
}
