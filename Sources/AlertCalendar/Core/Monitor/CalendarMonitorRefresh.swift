import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    private static let weatherLookAheadDays = 7

    func refreshUpcomingItems() async {
        await enqueueRefreshAndWait()
    }

    func refreshUpcomingItemsImpl() async {
        refreshAvailableCalendars()
        let settings = snapshotSettings()
        let now = fixedSecondNow()
        await refreshFootballDataIfNeeded(now: now)
        let endDate = now.addingTimeInterval(Double(settings.lookAheadHours) * 3600)

        var timedCollected: [UpcomingItem] = []
        var allDayCollected: [UpcomingItem] = []

        if hasEventsAccess, (settings.includeEvents || settings.includeAllDayEvents) {
            let selectedCalendars = calendarsForSelection(
                kind: .event,
                selectedIDs: settings.selectedEventCalendarIDs,
                weekdayOnlyIDs: settings.weekdayOnlyEventCalendarIDs,
                now: now
            )
            let lookBackHours = max(24, settings.lookAheadHours)
            let eventsStart = now.addingTimeInterval(-Double(lookBackHours) * 3600)
            let events = loadEvents(from: eventsStart, to: endDate, now: now, calendars: selectedCalendars)
            if settings.includeEvents {
                timedCollected.append(contentsOf: events.timedItems)
            }
            allDayCollected = settings.includeAllDayEvents ? events.allDayItems : []
        }

        if settings.includeReminders, hasRemindersAccess {
            let selectedCalendars = calendarsForSelection(
                kind: .reminder,
                selectedIDs: settings.selectedReminderCalendarIDs,
                weekdayOnlyIDs: settings.weekdayOnlyReminderCalendarIDs,
                now: now
            )
            let reminders = await loadReminders(from: nil, to: endDate, calendars: selectedCalendars)
            timedCollected.append(contentsOf: reminders)
        }

        if settings.includeWeather,
           let weatherItem = await weatherItemForRefresh(now: now, end: endDate, settings: settings) {
            let skippedWeatherUntilRaw = defaults.double(forKey: DefaultsKeys.skippedWeatherUntil)
            if skippedWeatherUntilRaw > 0 {
                let skippedWeatherUntil = Date(timeIntervalSince1970: skippedWeatherUntilRaw)
                if now >= skippedWeatherUntil {
                    defaults.removeObject(forKey: DefaultsKeys.skippedWeatherUntil)
                    timedCollected.append(weatherItem)
                } else if weatherItem.date >= skippedWeatherUntil {
                    timedCollected.append(weatherItem)
                }
            } else {
                timedCollected.append(weatherItem)
            }
        } else {
            cachedWeatherItem = nil
            lastWeatherFetchDate = nil
            weatherCacheSignature = nil
        }

        if settings.includeAstronomy {
            timedCollected.append(contentsOf: loadAstronomyItems(from: now, to: endDate, settings: settings))
        }

        timedCollected.sort { $0.date < $1.date }
        allDayCollected.sort { $0.date < $1.date }
        let deduplicatedTimedItems = deduplicatedItemsByNotificationKey(timedCollected)
        let deduplicatedAllDayItems = deduplicatedItemsByNotificationKey(allDayCollected)

        pruneSkippedKeys(using: deduplicatedTimedItems, allDayItems: deduplicatedAllDayItems)

        let visibleTimedItems = deduplicatedTimedItems.filter { !skippedItemKeys.contains($0.notificationKey) }
        let visibleAllDayItems = deduplicatedAllDayItems.filter { !skippedItemKeys.contains($0.notificationKey) }

        upcomingItems = visibleTimedItems
        allDayEventItems = visibleAllDayItems
        lastRefreshDate = now
        pruneAlertCaches(using: visibleTimedItems)
        evaluateAlert(now: now, settings: settings)
        updateMenuBarState(now: now, settings: settings)
    }

    func pruneSkippedKeys(using items: [UpcomingItem], allDayItems: [UpcomingItem] = []) {
        let validKeys = Set((items + allDayItems).map(\.notificationKey))
        let previous = skippedItemKeys
        skippedItemKeys.formIntersection(validKeys)
        if skippedItemKeys != previous {
            persistSkippedItemKeys()
        }
    }

    func deduplicatedItemsByNotificationKey(_ items: [UpcomingItem]) -> [UpcomingItem] {
        var seenKeys: Set<String> = []
        var deduplicated: [UpcomingItem] = []
        deduplicated.reserveCapacity(items.count)

        for item in items {
            if seenKeys.insert(item.notificationKey).inserted {
                deduplicated.append(item)
            }
        }

        return deduplicated
    }

    func skipItem(_ item: UpcomingItem) {
        skippedItemKeys.insert(item.notificationKey)
        persistSkippedItemKeys()
        if item.kind == .weather, let endDate = item.endDate {
            defaults.set(endDate.timeIntervalSince1970, forKey: DefaultsKeys.skippedWeatherUntil)
        }
        upcomingItems.removeAll { $0.notificationKey == item.notificationKey }
        allDayEventItems.removeAll { $0.notificationKey == item.notificationKey }
        if activeAlertItem?.notificationKey == item.notificationKey {
            activeAlertItem = nil
            blinkPhase = false
        }

        let now = fixedSecondNow()
        let settings = snapshotSettings()
        evaluateAlert(now: now, settings: settings)
        updateMenuBarState(now: now, settings: settings)
    }

    func hasSkippedItems() -> Bool {
        !skippedItemKeys.isEmpty
    }

    func restoreSkippedItems() {
        guard !skippedItemKeys.isEmpty else { return }
        skippedItemKeys.removeAll()
        persistSkippedItemKeys()
        refreshNow()
    }

    func persistSkippedItemKeys() {
        let newValue = Array(skippedItemKeys).sorted()
        let currentValue = (defaults.stringArray(forKey: DefaultsKeys.skippedItemKeys) ?? []).sorted()
        guard newValue != currentValue else { return }
        defaults.set(newValue, forKey: DefaultsKeys.skippedItemKeys)
    }

    func weatherItemForRefresh(now: Date, end: Date, settings: SettingsSnapshot) async -> UpcomingItem? {
        let refreshInterval: TimeInterval = 5 * 60
        let signature = "\(settings.astronomyLatitude)|\(settings.astronomyLongitude)|\(settings.lookAheadHours)"
        let shouldFetchFresh: Bool
        let weatherHorizonEnd = now.addingTimeInterval(Double(Self.weatherLookAheadDays) * 86_400)

        if weatherCacheSignature != signature {
            shouldFetchFresh = true
        } else if let lastWeatherFetchDate {
            shouldFetchFresh = now.timeIntervalSince(lastWeatherFetchDate) >= refreshInterval
        } else {
            shouldFetchFresh = true
        }

        if shouldFetchFresh {
            cachedWeatherItem = await loadWeatherRainItem(now: now, end: weatherHorizonEnd, settings: settings)
            lastWeatherFetchDate = now
            weatherCacheSignature = signature
        }

        guard let cachedWeatherItem else { return nil }
        guard cachedWeatherItem.date <= weatherHorizonEnd else { return nil }
        if let weatherEnd = cachedWeatherItem.endDate, weatherEnd <= now {
            return nil
        }
        return cachedWeatherItem
    }

    func markReminderCompleted(_ item: UpcomingItem) {
        guard item.kind == .reminder else { return }
        guard hasRemindersAccess else { return }

        guard let reminder = eventStore.calendarItem(withIdentifier: item.id) as? EKReminder else {
            skipItem(item)
            return
        }

        reminder.isCompleted = true
        reminder.completionDate = Date()

        do {
            try eventStore.save(reminder, commit: true)
            skipItem(item)
            refreshNow()
        } catch {
            calendarAccessDescription = "Could not mark reminder as completed."
        }
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
            let showsMutedBackground = requiresMutedParticipationStyle(for: event)
            let meetingURL = meetingURL(for: event)
            let locationText = normalizedLocation(for: event.location)
            let footballMenuBarDisplay = footballMatch.map(footballMenuBarDisplay(for:))
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

    func normalizedTravelTimeMinutes(for event: EKEvent, meetingURL: URL?, locationText: String?) -> Int? {
        // Virtual meetings should not be treated as trips to a physical place.
        if meetingURL != nil || isVirtualLocationText(locationText) {
            return nil
        }

        let hasLocationContext = event.structuredLocation != nil || normalizedLocation(for: event.location) != nil
        guard hasLocationContext else { return nil }

        // Prefer native travel time when available through Objective-C runtime.
        if let raw = (event as NSObject).value(forKey: "travelTime") as? NSNumber {
            let seconds = max(0, raw.doubleValue)
            if seconds >= 60 {
                return max(1, Int(ceil(seconds / 60.0)))
            }
        } else if let raw = (event as NSObject).value(forKey: "travelTime") as? Double, raw >= 60 {
            return max(1, Int(ceil(raw / 60.0)))
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
        guard let rawText else { return false }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let normalized = text.lowercased()

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
            return true
        }

        return allURLs(in: text).contains(where: isKnownMeetingURL)
    }

    func meetingURL(for event: EKEvent) -> URL? {
        var candidates: [URL] = []
        if let url = event.url {
            candidates.append(url)
        }
        if let notes = event.notes {
            candidates.append(contentsOf: allURLs(in: notes))
        }
        if let location = event.location {
            candidates.append(contentsOf: allURLs(in: location))
        }

        return MeetingURLResolver.bestMeetingURL(from: candidates)
    }

    func allURLs(in text: String) -> [URL] {
        MeetingURLResolver.allURLs(in: text)
    }

    func resolvedMeetingURL(from url: URL) -> URL? {
        MeetingURLResolver.resolvedMeetingURL(from: url)
    }

    func resolvedMeetingURLCandidates(from url: URL) -> [URL] {
        MeetingURLResolver.resolvedMeetingURLCandidates(from: url)
    }

    func collectMeetingURLCandidates(from url: URL, results: inout [URL], visited: inout Set<String>) {
        for candidate in MeetingURLResolver.resolvedMeetingURLCandidates(from: url) {
            let key = candidate.absoluteString
            guard visited.insert(key).inserted else { continue }
            results.append(candidate)
        }
    }

    func meetingURLScore(_ url: URL) -> Int {
        MeetingURLResolver.meetingURLScore(url)
    }

    func isKnownMeetingURL(_ url: URL) -> Bool {
        MeetingURLResolver.isKnownMeetingURL(url)
    }

    func isCalendarSelected(_ calendar: AvailableCalendar) -> Bool {
        selectedCalendarIDs(for: calendar.kind).contains(calendar.id)
    }

    func setCalendarSelected(_ calendar: AvailableCalendar, isSelected: Bool) {
        var ids = selectedCalendarIDs(for: calendar.kind)
        var weekdayOnlyIDs = weekdayOnlyCalendarIDs(for: calendar.kind)
        if isSelected {
            ids.insert(calendar.id)
        } else {
            ids.remove(calendar.id)
            weekdayOnlyIDs.remove(calendar.id)
        }

        defaults.set(Array(ids), forKey: calendar.kind == .event ? DefaultsKeys.selectedEventCalendarIDs : DefaultsKeys.selectedReminderCalendarIDs)
        defaults.set(Array(weekdayOnlyIDs), forKey: calendar.kind == .event ? DefaultsKeys.weekdayOnlyEventCalendarIDs : DefaultsKeys.weekdayOnlyReminderCalendarIDs)
        refreshNow()
    }

    func refreshAvailableCalendars() {
        if hasEventsAccess {
            let eventCalendars = eventStore.calendars(for: .event)
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            birthdayCalendarIDs = Set(
                eventCalendars
                    .filter { $0.type == .birthday }
                    .map(\.calendarIdentifier)
            )
            availableEventCalendars = eventCalendars.map {
                AvailableCalendar(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    color: color(from: $0),
                    kind: .event,
                    accountTitle: normalizedAccountTitle(for: $0),
                    isSubscribed: $0.type == .subscription
                )
            }
            syncStoredSelection(
                for: .event,
                availableIDs: Set(eventCalendars.map(\.calendarIdentifier))
            )
        } else {
            availableEventCalendars = []
            birthdayCalendarIDs = []
        }

        if hasRemindersAccess {
            let reminderCalendars = eventStore.calendars(for: .reminder)
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            availableReminderCalendars = reminderCalendars.map {
                AvailableCalendar(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    color: color(from: $0),
                    kind: .reminder,
                    accountTitle: normalizedAccountTitle(for: $0),
                    isSubscribed: $0.type == .subscription
                )
            }
            syncStoredSelection(
                for: .reminder,
                availableIDs: Set(reminderCalendars.map(\.calendarIdentifier))
            )
        } else {
            availableReminderCalendars = []
        }
    }

    func calendarsForSelection(
        kind: CalendarItemKind,
        selectedIDs: Set<String>,
        weekdayOnlyIDs: Set<String> = [],
        now: Date = Date()
    ) -> [EKCalendar] {
        let includeWeekdayOnlyToday = isWeekday(now)
        return eventStore.calendars(for: kind == .event ? .event : .reminder)
            .filter { calendar in
                let calendarID = calendar.calendarIdentifier
                guard selectedIDs.contains(calendarID) else { return false }
                if weekdayOnlyIDs.contains(calendarID) {
                    return includeWeekdayOnlyToday
                }
                return true
            }
    }

    func syncStoredSelection(for kind: CalendarItemKind, availableIDs: Set<String>) {
        syncStoredSelection(
            selectedKey: kind == .event ? DefaultsKeys.selectedEventCalendarIDs : DefaultsKeys.selectedReminderCalendarIDs,
            weekdayOnlyKey: kind == .event ? DefaultsKeys.weekdayOnlyEventCalendarIDs : DefaultsKeys.weekdayOnlyReminderCalendarIDs,
            availableIDs: availableIDs
        )
    }

    func selectedCalendarIDs(for kind: CalendarItemKind) -> Set<String> {
        let key = kind == .event ? DefaultsKeys.selectedEventCalendarIDs : DefaultsKeys.selectedReminderCalendarIDs
        return Set(defaults.stringArray(forKey: key) ?? [])
    }

    func weekdayOnlyCalendarIDs(for kind: CalendarItemKind) -> Set<String> {
        let key = kind == .event ? DefaultsKeys.weekdayOnlyEventCalendarIDs : DefaultsKeys.weekdayOnlyReminderCalendarIDs
        return Set(defaults.stringArray(forKey: key) ?? [])
    }

    private func syncStoredSelection(selectedKey: String, weekdayOnlyKey: String, availableIDs: Set<String>) {
        guard !availableIDs.isEmpty else { return }

        let sortedAvailableIDs = Array(availableIDs).sorted()
        let recoveryKey = selectedKey == DefaultsKeys.selectedEventCalendarIDs
            ? DefaultsKeys.didAutoRecoverEmptyEventCalendarSelection
            : DefaultsKeys.didAutoRecoverEmptyReminderCalendarSelection

        if defaults.object(forKey: selectedKey) == nil {
            defaults.set(sortedAvailableIDs, forKey: selectedKey)
        } else if let stored = defaults.stringArray(forKey: selectedKey) {
            let filtered = stored.filter { availableIDs.contains($0) }
            if filtered.isEmpty,
               !stored.isEmpty,
               !defaults.bool(forKey: recoveryKey) {
                defaults.set(sortedAvailableIDs, forKey: selectedKey)
                defaults.set(true, forKey: recoveryKey)
            } else if filtered.isEmpty,
                      stored.isEmpty,
                      !defaults.bool(forKey: recoveryKey) {
                defaults.set(sortedAvailableIDs, forKey: selectedKey)
                defaults.set(true, forKey: recoveryKey)
            } else if filtered != stored {
                defaults.set(filtered, forKey: selectedKey)
            }
        } else {
            defaults.set(sortedAvailableIDs, forKey: selectedKey)
        }

        if let weekdayOnlyStored = defaults.stringArray(forKey: weekdayOnlyKey) {
            let filteredWeekdayOnly = weekdayOnlyStored.filter { availableIDs.contains($0) }
            if filteredWeekdayOnly != weekdayOnlyStored {
                defaults.set(filteredWeekdayOnly, forKey: weekdayOnlyKey)
            }
        } else if defaults.object(forKey: weekdayOnlyKey) == nil {
            defaults.set([], forKey: weekdayOnlyKey)
        }
    }

    func isWeekday(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return (2 ... 6).contains(weekday)
    }

    func normalizedAccountTitle(for calendar: EKCalendar) -> String {
        let raw = calendar.source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Other Account" : raw
    }
}
