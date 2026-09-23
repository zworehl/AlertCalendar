import AppKit
import CoreLocation
import EventKit
import Foundation

struct CalendarMonitorReminderFetchResult {
    let reminders: [EKReminder]
    let timedOut: Bool
}

struct CalendarMonitorReminderLoadResult {
    let items: [UpcomingItem]
    let timedOut: Bool
}

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
            let showsMutedBackground = eventParticipationStatus?.appleCalendarStyle.usesTexture == true
            let meetingURL = meetingURL(for: event)
            let locationText = Self.preferredLocationText(
                eventLocation: event.location,
                structuredLocationTitle: event.structuredLocation?.title,
                footballMatchLocation: footballMatch?.locationText
            )
            let locationCoordinate = Self.nativeLocationCoordinate(for: event)
            let footballMenuBarDisplay = footballMatch.map(footballMenuBarDisplay(for:))
            let gameStore = event.isAllDay ? event.url.flatMap(Self.gameStore(for:)) : nil
            let organizer = organizer(for: event)
            let attendees = invitees(for: event)
            let isRecurring = isRecurringEvent(event)
            let agendaSummaryAttachments = Self.agendaSummaryAttachments(for: event)
            let hasDocumentIndicator = !agendaSummaryAttachments.isEmpty
                || hasDocumentIndicator(for: event, meetingURL: meetingURL)
            let urlMetadata = Self.calendarItemURLMetadata(
                eventURL: event.url,
                notes: event.notes,
                location: event.location,
                meetingURL: meetingURL
            )
            let agendaSummaryURLCandidates = Self.agendaSummaryURLCandidates(
                eventURL: event.url,
                notes: event.notes,
                location: event.location,
                meetingURL: meetingURL
            )
            let openLinkURL = Self.preferredOpenLinkURL(
                eventURL: event.url,
                notes: event.notes,
                location: event.location,
                meetingURL: meetingURL
            )
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
                        locationCoordinate: locationCoordinate,
                        meetingURL: meetingURL,
                        openLinkURL: openLinkURL,
                        urlCount: urlMetadata.count,
                        urlHosts: urlMetadata.hosts,
                        agendaSummaryURLCandidates: agendaSummaryURLCandidates,
                        agendaSummaryAttachments: agendaSummaryAttachments,
                        organizer: organizer,
                        attendees: attendees,
                        eventParticipationStatus: eventParticipationStatus,
                        isRecurring: isRecurring,
                        hasDocumentIndicator: hasDocumentIndicator,
                        descriptionText: event.notes,
                        lastModifiedAt: event.lastModifiedDate,
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
                    locationCoordinate: locationCoordinate,
                    meetingURL: meetingURL,
                    openLinkURL: openLinkURL,
                    urlCount: urlMetadata.count,
                    urlHosts: urlMetadata.hosts,
                    agendaSummaryURLCandidates: agendaSummaryURLCandidates,
                    agendaSummaryAttachments: agendaSummaryAttachments,
                    organizer: organizer,
                    attendees: attendees,
                    eventParticipationStatus: eventParticipationStatus,
                    isRecurring: isRecurring,
                    hasDocumentIndicator: hasDocumentIndicator,
                    descriptionText: event.notes,
                    lastModifiedAt: event.lastModifiedDate,
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

        timedItems.sort { UpcomingItem.sortPrecedes($0, $1) }
        allDayItems.sort { UpcomingItem.sortPrecedes($0, $1) }
        return (timedItems, allDayItems)
    }

    nonisolated static func preferredLocationText(
        eventLocation: String?,
        structuredLocationTitle: String? = nil,
        footballMatchLocation: String?
    ) -> String? {
        if let footballLocation = normalizedLocationText(footballMatchLocation) {
            return footballLocation
        }

        if let eventLocation = normalizedLocationText(eventLocation),
           !containsWebURL(in: eventLocation) {
            return eventLocation
        }

        if let structuredLocationTitle = normalizedLocationText(structuredLocationTitle),
           !containsWebURL(in: structuredLocationTitle) {
            return structuredLocationTitle
        }

        return nil
    }

    nonisolated static func nativeLocationCoordinate(for event: EKEvent) -> ResolvedLocationCoordinate? {
        guard let coordinate = event.structuredLocation?.geoLocation?.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }

        return ResolvedLocationCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private nonisolated static func normalizedLocationText(_ rawLocation: String?) -> String? {
        AlertCalendarString.trimmedNonEmpty(rawLocation)
    }

    func loadReminders(from start: Date?, to end: Date, calendars: [EKCalendar]) async -> CalendarMonitorReminderLoadResult {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: start,
            ending: end,
            calendars: calendars
        )

        let result = await fetchReminders(
            matching: predicate,
            timeout: CalendarMonitorCadence.reminderFetchTimeoutInterval
        )

        let items = result.reminders.compactMap { reminder -> UpcomingItem? in
            guard let dueDate = dueDate(for: reminder) else { return nil }
            let hasExplicitTime = reminderHasExplicitTime(reminder)
            let agendaSummaryAttachments = Self.agendaSummaryAttachments(for: reminder)
            let urlMetadata = Self.calendarItemURLMetadata(
                eventURL: reminder.url,
                notes: reminder.notes,
                meetingURL: nil
            )
            let agendaSummaryURLCandidates = Self.agendaSummaryURLCandidates(
                eventURL: reminder.url,
                notes: reminder.notes,
                meetingURL: nil
            )
            let openLinkURL = Self.preferredOpenLinkURL(
                eventURL: reminder.url,
                notes: reminder.notes,
                meetingURL: nil
            )
            return UpcomingItem(
                id: reminder.calendarItemIdentifier,
                title: normalizedTitle(reminder.title),
                date: dueDate,
                endDate: nil,
                isAllDay: false,
                hasExplicitTime: hasExplicitTime,
                showsMutedBackground: false,
                travelTimeMinutes: nil,
                locationText: nil,
                meetingURL: nil,
                openLinkURL: openLinkURL,
                urlCount: urlMetadata.count,
                urlHosts: urlMetadata.hosts,
                agendaSummaryURLCandidates: agendaSummaryURLCandidates,
                agendaSummaryAttachments: agendaSummaryAttachments,
                organizer: nil,
                attendees: [],
                isRecurring: isRecurringReminder(reminder),
                hasDocumentIndicator: !agendaSummaryAttachments.isEmpty
                    || Self.hasDocumentIndicator(
                        eventURL: reminder.url,
                        notes: reminder.notes,
                        meetingURL: nil
                    ),
                descriptionText: reminder.notes,
                lastModifiedAt: reminder.lastModifiedDate,
                calendarID: reminder.calendar.calendarIdentifier,
                calendarName: reminder.calendar.title,
                calendarColor: color(from: reminder.calendar),
                kind: .reminder,
                footballMatch: nil,
                footballMenuBarDisplay: nil
            )
        }
        return CalendarMonitorReminderLoadResult(items: items, timedOut: result.timedOut)
    }

    func fetchReminders(
        matching predicate: NSPredicate,
        timeout: TimeInterval
    ) async -> CalendarMonitorReminderFetchResult {
        await withCheckedContinuation { continuation in
            var didResume = false

            func resumeOnce(with reminders: [EKReminder], timedOut: Bool = false) {
                guard !didResume else { return }
                didResume = true
                if timedOut {
                    CalendarMonitorLog.refresh.error("Timed out fetching reminders from EventKit")
                }
                continuation.resume(
                    returning: CalendarMonitorReminderFetchResult(
                        reminders: reminders,
                        timedOut: timedOut
                    )
                )
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

    func cachedReminderItems(to endDate: Date, calendars: [EKCalendar]) -> [UpcomingItem] {
        let selectedCalendarIDs = Set(calendars.map(\.calendarIdentifier))
        return lastSuccessfulReminderItems.filter { item in
            guard let calendarID = item.calendarID else { return false }
            return selectedCalendarIDs.contains(calendarID) && item.date <= endDate
        }
    }

    func scheduleReminderRefresh(to endDate: Date, calendars: [EKCalendar]) {
        let calendarIDs = calendars.map(\.calendarIdentifier).sorted()
        let fingerprint = (calendarIDs + [String(Int(endDate.timeIntervalSince1970 / 60))])
            .joined(separator: "|")
        if reminderRefreshTask != nil, reminderRefreshFingerprint == fingerprint {
            return
        }

        reminderRefreshTask?.cancel()
        let token = UUID()
        reminderRefreshToken = token
        reminderRefreshFingerprint = fingerprint
        reminderRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await loadReminders(from: nil, to: endDate, calendars: calendars)
            guard !Task.isCancelled, reminderRefreshToken == token else { return }

            reminderRefreshTask = nil
            reminderRefreshToken = nil
            reminderRefreshFingerprint = nil
            dataRefreshHealthState.reminderError = result.timedOut ? "Reminders did not respond in time. Keeping the last available reminders." : nil
            guard !result.timedOut else { return }

            let sortedItems = result.items.sorted { UpcomingItem.sortPrecedes($0, $1) }
            guard sortedItems != lastSuccessfulReminderItems else { return }
            lastSuccessfulReminderItems = sortedItems
            enqueueRefresh(reason: .remindersChanged)
        }
    }

    func cancelReminderRefresh(clearCachedItems: Bool) {
        reminderRefreshTask?.cancel()
        reminderRefreshTask = nil
        reminderRefreshToken = nil
        reminderRefreshFingerprint = nil
        if clearCachedItems {
            lastSuccessfulReminderItems = []
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
        Self.eventParticipationStatus(
            currentUserParticipantStatus: event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus,
            eventStatus: event.status,
            eventAvailability: event.availability,
            organizerIsCurrentUser: event.organizer?.isCurrentUser
        )
    }

    nonisolated static func eventParticipationStatus(
        currentUserParticipantStatus: EKParticipantStatus?,
        eventStatus: EKEventStatus,
        eventAvailability: EKEventAvailability,
        organizerIsCurrentUser: Bool?
    ) -> EventParticipationStatus? {
        if let currentUserParticipantStatus {
            return eventParticipationStatus(for: currentUserParticipantStatus)
        }

        // Some calendar providers omit the current-user attendee flag. An external
        // organizer still identifies the event as an invitation awaiting a response.
        // This must take precedence over the event's generic availability, which can
        // be tentative even when the current user has not responded.
        if organizerIsCurrentUser == false {
            return .pending
        }

        if eventStatus == .tentative || eventAvailability == .tentative {
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
