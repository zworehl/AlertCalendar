import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    private static let allDayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let allDayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<CalendarMonitor, T>, to newValue: T) {
        if self[keyPath: keyPath] != newValue {
            self[keyPath: keyPath] = newValue
        }
    }

    private func setColorIfChanged(_ keyPath: ReferenceWritableKeyPath<CalendarMonitor, NSColor>, to newValue: NSColor) {
        let current = self[keyPath: keyPath]
        if !current.isEqual(newValue) {
            self[keyPath: keyPath] = newValue
        }
    }

    private func setColorArrayIfChanged(_ keyPath: ReferenceWritableKeyPath<CalendarMonitor, [NSColor]>, to newValue: [NSColor]) {
        let current = self[keyPath: keyPath]
        guard current.count == newValue.count else {
            self[keyPath: keyPath] = newValue
            return
        }

        let differs = zip(current, newValue).contains { left, right in
            !left.isEqual(right)
        }
        if differs {
            self[keyPath: keyPath] = newValue
        }
    }

    func evaluateAlert(now: Date, settings: SettingsSnapshot) {
        let leadSeconds = TimeInterval(max(1, settings.alertLeadMinutes) * 60)
        guard let candidate = upcomingItems.first(where: {
            guard $0.kind != .weather else { return false }
            guard AstronomyMoment(eventTitle: $0.title) == nil else { return false }
            let remaining = $0.date.timeIntervalSince(now)
            return remaining > 0 && remaining <= leadSeconds
        }) else {
            setIfChanged(\.activeAlertItem, to: nil)
            blinkPhase = false
            return
        }

        if silencedAlertKeys.contains(candidate.notificationKey) {
            setIfChanged(\.activeAlertItem, to: nil)
            blinkPhase = false
            return
        }

        setIfChanged(\.activeAlertItem, to: candidate)
        if settings.enableBlinkAlert {
            blinkPhase.toggle()
        } else {
            blinkPhase = false
        }

        if !alreadyNotified.contains(candidate.notificationKey) {
            alreadyNotified.insert(candidate.notificationKey)
            triggerLocalBeep()
        }
    }

    func triggerLocalBeep() {
        NSSound.beep()
    }

    func pruneAlertCaches(using items: [UpcomingItem]) {
        let validKeys = Set(items.map(\.notificationKey))
        alreadyNotified.formIntersection(validKeys)
        silencedAlertKeys.formIntersection(validKeys)
    }

    func updateMenuBarState(now: Date, settings: SettingsSnapshot) {
        if let highlight = activeFootballGoalHighlight,
           highlight.expiresAt <= now {
            activeFootballGoalHighlight = nil
        }

        let previewItems = displayedItemsForMenuBar(now: now, settings: settings)
        if previewItems.isEmpty {
            setIfChanged(\.combinedMenuBarLabel, to: "No upcoming items")
            setColorIfChanged(\.combinedMenuBarColor, to: .systemGray)
            setIfChanged(\.combinedMenuBarAlertedSegmentIndex, to: nil)
            setIfChanged(\.combinedMenuBarAlertTextOpacity, to: 0)
            setColorArrayIfChanged(\.combinedMenuBarDotColors, to: [.systemGray])
            setIfChanged(\.combinedMenuBarMarkerStyles, to: [.color(.systemGray)])
            setIfChanged(\.combinedMenuBarSegments, to: ["No upcoming items"])
            setColorArrayIfChanged(\.combinedMenuBarSegmentBackgroundColors, to: [.clear])
            setIfChanged(\.combinedMenuBarSegmentBackgroundProgresses, to: [0])
        } else {
            setColorIfChanged(\.combinedMenuBarColor, to: previewItems[0].calendarColor)
            setColorArrayIfChanged(\.combinedMenuBarDotColors, to: previewItems.map(\.calendarColor))
            setIfChanged(\.combinedMenuBarMarkerStyles, to: previewItems.map { markerStyle(for: $0) })
            let segmentBackgrounds = previewItems.map { segmentBackgroundVisual(for: $0, now: now, settings: settings) }
            setColorArrayIfChanged(\.combinedMenuBarSegmentBackgroundColors, to: segmentBackgrounds.map(\.color))
            setIfChanged(\.combinedMenuBarSegmentBackgroundProgresses, to: segmentBackgrounds.map(\.progress))
            let segments = previewItems.map {
                menuSegment(
                    for: $0,
                    now: now,
                    simplified: settings.useSimplifiedCountdown,
                    activeEventDisplayMode: settings.activeEventDisplayMode,
                    useEventTitleEllipsis: settings.useEventTitleEllipsis,
                    eventTitleMaxCharacters: settings.eventTitleMaxCharacters
                )
            }

            if settings.enableBlinkAlert,
               let activeAlertItem,
               let alertIndex = previewItems.firstIndex(where: { $0.notificationKey == activeAlertItem.notificationKey }) {
                setIfChanged(\.combinedMenuBarAlertedSegmentIndex, to: alertIndex)
                setIfChanged(\.combinedMenuBarAlertTextOpacity, to: blinkPhase ? 1.0 : 0.0)
            } else {
                setIfChanged(\.combinedMenuBarAlertedSegmentIndex, to: nil)
                setIfChanged(\.combinedMenuBarAlertTextOpacity, to: 0)
            }

            setIfChanged(\.combinedMenuBarSegments, to: segments)
            setIfChanged(\.combinedMenuBarLabel, to: segments.joined(separator: "  "))
        }

        let nextEvent = rotatingTimedItem(now: now, settings: settings)
        let nextReminder = rotatingReminderItem(now: now, settings: settings)

        setColorIfChanged(\.eventsMenuBarColor, to: nextEvent?.calendarColor ?? .systemGray)
        setColorIfChanged(\.remindersMenuBarColor, to: nextReminder?.calendarColor ?? .systemGray)

        setIfChanged(\.eventsMenuBarLabel, to: menuLabel(
            for: nextEvent,
            now: now,
            simplified: settings.useSimplifiedCountdown,
            activeEventDisplayMode: settings.activeEventDisplayMode,
            useEventTitleEllipsis: settings.useEventTitleEllipsis,
            eventTitleMaxCharacters: settings.eventTitleMaxCharacters,
            fallback: "No events"
        ))

        setIfChanged(\.remindersMenuBarLabel, to: menuLabel(
            for: nextReminder,
            now: now,
            simplified: settings.useSimplifiedCountdown,
            activeEventDisplayMode: settings.activeEventDisplayMode,
            useEventTitleEllipsis: settings.useEventTitleEllipsis,
            eventTitleMaxCharacters: settings.eventTitleMaxCharacters,
            fallback: "No reminders"
        ))
    }

    func menuLabel(
        for item: UpcomingItem?,
        now: Date,
        simplified: Bool,
        activeEventDisplayMode: ActiveEventDisplayMode,
        useEventTitleEllipsis: Bool,
        eventTitleMaxCharacters: Int,
        fallback: String
    ) -> String {
        guard let item else { return fallback }
        return menuSegment(
            for: item,
            now: now,
            simplified: simplified,
            activeEventDisplayMode: activeEventDisplayMode,
            useEventTitleEllipsis: useEventTitleEllipsis,
            eventTitleMaxCharacters: eventTitleMaxCharacters
        )
    }

    func menuSegment(
        for item: UpcomingItem,
        now: Date,
        simplified: Bool,
        activeEventDisplayMode: ActiveEventDisplayMode,
        useEventTitleEllipsis: Bool,
        eventTitleMaxCharacters: Int
    ) -> String {
        let compactTitle: String
        if useEventTitleEllipsis {
            compactTitle = trimmedTitle(item.title, maxLength: max(1, eventTitleMaxCharacters))
        } else {
            compactTitle = item.title
        }

        if let footballMatch = item.footballMatch,
           footballMatch.statusState != .scheduled || item.date <= now {
            return compactTitle
        }

        if item.kind == .event,
           item.date <= now,
           (item.endDate ?? item.date) > now,
           FootballFixtureFormatter.looksLikeFootballCalendarTitle(item.title) {
            return compactTitle
        }

        if item.kind == .weather {
            if let endDate = item.endDate, endDate > item.date {
                if item.date <= now, endDate > now {
                    let elapsed = elapsedCountdown(from: item.date, to: now, simplified: simplified)
                    let remaining = relativeCountdown(to: endDate, from: now, simplified: simplified)
                    return "\(compactTitle) \(elapsed) elapsed, \(remaining) left"
                }
                let duration = relativeCountdown(to: endDate, from: item.date, simplified: simplified)
                return "\(compactTitle) in about \(relativeCountdown(to: item.date, from: now, simplified: simplified)) for \(duration)"
            }
            return "\(compactTitle) in about \(relativeCountdown(to: item.date, from: now, simplified: simplified))"
        }
        if item.isAllDay {
            if isBirthdayItem(item) {
                return compactTitle
            }
            let allDayDetail = allDayLabel(for: item) ?? "all-day"
            return "\(compactTitle) \(allDayDetail)"
        }
        if item.kind == .reminder, item.date <= now {
            return "\(compactTitle) \(elapsedCountdown(from: item.date, to: now, simplified: simplified)) ago"
        }
        if item.kind == .event, let endDate = item.endDate, item.date <= now, endDate > now {
            switch activeEventDisplayMode {
            case .remaining:
                return "\(compactTitle) \(relativeCountdown(to: endDate, from: now, simplified: simplified)) left"
            case .elapsed:
                return "\(compactTitle) started \(elapsedCountdown(from: item.date, to: now, simplified: simplified)) ago"
            }
        }
        return "\(compactTitle) in \(relativeCountdown(to: item.date, from: now, simplified: simplified))"
    }

    func isBirthdayItem(_ item: UpcomingItem) -> Bool {
        guard item.kind == .event, let calendarID = item.calendarID else { return false }
        return birthdayCalendarIDs.contains(calendarID)
    }

    func displayedItemsForMenuBar(now: Date, settings: SettingsSnapshot) -> [UpcomingItem] {
        let queue = unifiedMenuBarQueue(now: now, settings: settings)
        guard !queue.isEmpty else { return [] }

        if let highlight = activeFootballGoalHighlight,
           highlight.expiresAt > now,
           let highlightedItem = queue.first(where: { $0.footballMatch?.id == highlight.matchID }) {
            return [highlightedItem]
        }

        let pool = preferredMenuBarRotationPool(from: queue, now: now, settings: settings)
        guard !pool.isEmpty else { return [] }
        guard pool.count > 1 else { return [pool[0]] }

        let rotationSeconds = max(5, settings.concurrentEventRotationSeconds)
        let slot = rotationSlot(now: now, seconds: rotationSeconds)
        let rotatingIndex = abs(slot) % pool.count
        return [pool[rotatingIndex]]
    }

    func primaryReminderItem(now: Date) -> UpcomingItem? {
        let reminders = upcomingItems.filter { $0.kind == .reminder }
        if let upcoming = reminders.first(where: { $0.date >= now }) {
            return upcoming
        }
        return reminders.last(where: { $0.date < now })
    }

    func rotatingReminderItem(now: Date, settings: SettingsSnapshot) -> UpcomingItem? {
        let reminders = upcomingItems.filter { $0.kind == .reminder }
        guard !reminders.isEmpty else { return nil }

        let nearUpcomingLeadSeconds = TimeInterval(max(5, settings.nearUpcomingAlternateMinutes) * 60)
        let rotationSeconds = max(5, settings.concurrentEventRotationSeconds)
        let slot = rotationSlot(now: now, seconds: rotationSeconds)

        let overdueReminders = reminders.filter { $0.date <= now }
        let nearUpcomingReminders = reminders.filter { item in
            item.date > now && item.date.timeIntervalSince(now) <= nearUpcomingLeadSeconds
        }

        if !overdueReminders.isEmpty {
            let rotatingPool = deduplicatedItemsByNotificationKey(overdueReminders + nearUpcomingReminders)
            guard !rotatingPool.isEmpty else { return reminders[0] }
            let rotatingIndex = abs(slot) % rotatingPool.count
            return rotatingPool[rotatingIndex]
        }

        if !nearUpcomingReminders.isEmpty {
            let rotatingPool = deduplicatedItemsByNotificationKey(nearUpcomingReminders)
            let rotatingIndex = abs(slot) % rotatingPool.count
            return rotatingPool[rotatingIndex]
        }

        let upcomingReminders = reminders.filter { $0.date >= now }
        let baseList = upcomingReminders.isEmpty ? reminders.filter { $0.date < now } : upcomingReminders
        guard let firstItem = baseList.first else { return nil }

        let calendar = Calendar.current
        let concurrentItems = baseList.filter {
            calendar.isDate($0.date, equalTo: firstItem.date, toGranularity: .minute)
        }
        guard concurrentItems.count > 1 else { return firstItem }
        let rotatingIndex = abs(slot) % concurrentItems.count
        return concurrentItems[rotatingIndex]
    }

    func rotatingAllDayEventItem(now: Date, settings: SettingsSnapshot) -> UpcomingItem? {
        guard !allDayEventItems.isEmpty else { return nil }
        guard allDayEventItems.count > 1 else { return allDayEventItems[0] }

        let rotationSeconds = max(5, settings.concurrentEventRotationSeconds)
        let slot = rotationSlot(now: now, seconds: rotationSeconds)
        let rotatingIndex = abs(slot) % allDayEventItems.count
        return allDayEventItems[rotatingIndex]
    }

    func rotatingTimedItem(now: Date, settings: SettingsSnapshot) -> UpcomingItem? {
        let timedItems = upcomingItems.filter { isTimedItemDisplayableInMenuBar($0, now: now) }
        guard !timedItems.isEmpty else { return nil }

        let nearUpcomingLeadSeconds = TimeInterval(max(1, settings.nearUpcomingAlternateMinutes) * 60)
        let concurrentRotationInterval = max(5, settings.concurrentEventRotationSeconds)
        let timeSlot = rotationSlot(now: now, seconds: concurrentRotationInterval)

        let ongoingEvents = timedItems.filter { item in
            item.endDate.map { item.date <= now && $0 > now } ?? false
        }
        if ongoingEvents.count > 1 {
            let nearUpcomingEvents = timedItems.filter { item in
                item.date > now && item.date.timeIntervalSince(now) <= nearUpcomingLeadSeconds
            }
            let rotatingPool = nearUpcomingEvents.isEmpty ? ongoingEvents : (ongoingEvents + nearUpcomingEvents)
            let rotatingIndex = abs(timeSlot) % rotatingPool.count
            return rotatingPool[rotatingIndex]
        }

        if let ongoingEvent = ongoingEvents.first,
           !timedItems.isEmpty {
            let nearUpcomingEvents = timedItems.filter { item in
               item.date > now && item.date.timeIntervalSince(now) <= nearUpcomingLeadSeconds
            }
            if !nearUpcomingEvents.isEmpty {
                let rotatingPool = [ongoingEvent] + nearUpcomingEvents
                let rotatingIndex = abs(timeSlot) % rotatingPool.count
                return rotatingPool[rotatingIndex]
            }
        }

        let firstItem = timedItems[0]
        let calendar = Calendar.current
        let concurrentItems = timedItems.filter {
            calendar.isDate($0.date, equalTo: firstItem.date, toGranularity: .minute)
        }

        guard concurrentItems.count > 1 else {
            return firstItem
        }

        let rotatingIndex = abs(timeSlot) % concurrentItems.count
        return concurrentItems[rotatingIndex]
    }

    func rotationSlot(now: Date, seconds: Int) -> Int {
        let clamped = max(1, seconds)
        return Int(now.timeIntervalSince1970 / Double(clamped))
    }

    func menuBarPreviewItems(now: Date, settings: SettingsSnapshot) -> [UpcomingItem] {
        Array(unifiedMenuBarQueue(now: now, settings: settings).prefix(1))
    }

    private func unifiedMenuBarQueue(now: Date, settings: SettingsSnapshot) -> [UpcomingItem] {
        let timedItems = upcomingItems.filter { isTimedItemDisplayableInMenuBar($0, now: now) }
        let allDayItems = settings.includeAllDayEvents ? allDayEventItems : []
        let merged = deduplicatedItemsByNotificationKey(timedItems + allDayItems)

        return merged.sorted { left, right in
            let leftPriority = menuBarQueuePriority(for: left)
            let rightPriority = menuBarQueuePriority(for: right)
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            if left.date != right.date {
                return left.date < right.date
            }
            if left.kind != right.kind {
                return left.kind.rawValue < right.kind.rawValue
            }
            let titleOrder = left.title.localizedCaseInsensitiveCompare(right.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return left.notificationKey < right.notificationKey
        }
    }

    private func menuBarQueuePriority(for item: UpcomingItem) -> Int {
        item.isAllDay ? 1 : 0
    }

    private func preferredMenuBarRotationPool(
        from queue: [UpcomingItem],
        now: Date,
        settings: SettingsSnapshot
    ) -> [UpcomingItem] {
        let nearUpcomingLeadSeconds = TimeInterval(max(5, settings.nearUpcomingAlternateMinutes) * 60)
        let allDayEvents = queue.filter { item in
            item.kind == .event && item.isAllDay
        }

        let ongoingTimedEvents = queue.filter { item in
            guard item.kind == .event, !item.isAllDay else { return false }
            guard let endDate = item.endDate else { return false }
            return item.date <= now && endDate > now
        }

        let overdueReminders = queue.filter { item in
            item.kind == .reminder && item.date <= now
        }

        guard !ongoingTimedEvents.isEmpty || !allDayEvents.isEmpty || !overdueReminders.isEmpty else {
            return queue
        }

        let nearUpcomingTimedEvents = queue.filter { item in
            guard item.kind == .event, !item.isAllDay else { return false }
            guard item.date > now else { return false }
            return item.date.timeIntervalSince(now) <= nearUpcomingLeadSeconds
        }

        let nearUpcomingReminders = queue.filter { item in
            guard item.kind == .reminder else { return false }
            guard item.date > now else { return false }
            return item.date.timeIntervalSince(now) <= nearUpcomingLeadSeconds
        }

        let focusedKeys = Set((ongoingTimedEvents + overdueReminders + nearUpcomingTimedEvents + nearUpcomingReminders).map(\.notificationKey))
        let focusedPool = queue.filter { item in
            if item.kind == .event, item.isAllDay {
                return true
            }
            if item.kind == .event, !item.isAllDay {
                return focusedKeys.contains(item.notificationKey)
            }
            if item.kind == .reminder {
                return focusedKeys.contains(item.notificationKey)
            }
            return true
        }
        return focusedPool.isEmpty ? queue : focusedPool
    }

    private func isTimedItemDisplayableInMenuBar(_ item: UpcomingItem, now: Date) -> Bool {
        guard !item.isAllDay else { return false }

        if let endDate = item.endDate {
            return endDate > now
        }

        if item.kind == .reminder {
            return true
        }

        return item.date >= now
    }

    func snapshotSettings() -> SettingsSnapshot {
        return SettingsSnapshot(
            includeEvents: defaults.bool(forKey: DefaultsKeys.includeEvents),
            includeAllDayEvents: defaults.bool(forKey: DefaultsKeys.includeAllDayEvents),
            includeReminders: defaults.bool(forKey: DefaultsKeys.includeReminders),
            includeWeather: defaults.bool(forKey: DefaultsKeys.includeWeather),
            includeAstronomy: defaults.bool(forKey: DefaultsKeys.includeAstronomy),
            useAutomaticAstronomyLocation: defaults.bool(forKey: DefaultsKeys.useAutomaticAstronomyLocation),
            astronomyColorID: defaults.string(forKey: DefaultsKeys.astronomyColorID) ?? "blue",
            astronomyLatitude: defaults.double(forKey: DefaultsKeys.astronomyLatitude),
            astronomyLongitude: defaults.double(forKey: DefaultsKeys.astronomyLongitude),
            selectedEventCalendarIDs: selectedCalendarIDs(for: .event),
            selectedReminderCalendarIDs: selectedCalendarIDs(for: .reminder),
            weekdayOnlyEventCalendarIDs: weekdayOnlyCalendarIDs(for: .event),
            weekdayOnlyReminderCalendarIDs: weekdayOnlyCalendarIDs(for: .reminder),
            lookAheadHours: max(1, defaults.integer(forKey: DefaultsKeys.lookAheadHours)),
            alertLeadMinutes: max(1, defaults.integer(forKey: DefaultsKeys.alertLeadMinutes)),
            nearUpcomingAlternateMinutes: normalizedNearUpcomingAlternateMinutes(defaults.integer(forKey: DefaultsKeys.nearUpcomingAlternateMinutes)),
            concurrentEventRotationSeconds: max(5, defaults.integer(forKey: DefaultsKeys.concurrentEventRotationSeconds)),
            enableBlinkAlert: defaults.bool(forKey: DefaultsKeys.enableBlinkAlert),
            useSimplifiedCountdown: defaults.bool(forKey: DefaultsKeys.useSimplifiedCountdown),
            activeEventDisplayMode: ActiveEventDisplayMode(rawValue: defaults.string(forKey: DefaultsKeys.activeEventDisplayMode) ?? "") ?? .remaining,
            useEventTitleEllipsis: defaults.bool(forKey: DefaultsKeys.useEventTitleEllipsis),
            eventTitleMaxCharacters: max(1, defaults.integer(forKey: DefaultsKeys.eventTitleMaxCharacters))
        )
    }

    private func normalizedNearUpcomingAlternateMinutes(_ value: Int) -> Int {
        let clamped = max(5, min(120, value))
        return Int((Double(clamped) / 5.0).rounded()) * 5
    }

    func normalizedTitle(_ rawTitle: String?) -> String {
        guard let rawTitle else { return "(Untitled)" }
        let cleaned = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "(Untitled)" : cleaned
    }

    func markerStyle(for item: UpcomingItem) -> MenuMarkerStyle {
        if item.kind == .reminder {
            return .reminder(item.calendarColor)
        }
        if item.kind == .weather {
            switch item.title.lowercased() {
            case "drizzle":
                return .drizzle
            case "thunderstorm":
                return .thunderstorm
            default:
                return .rain
            }
        }
        if isBirthdayItem(item) {
            return .birthday(item.calendarColor)
        }
        if item.kind == .event, item.isAllDay {
            return .allDay(item.calendarColor)
        }

        switch item.title.lowercased() {
        case "sunrise":
            return .sunrise
        case "solar noon":
            return .solarNoon
        case "sunset":
            return .sunset
        case "solar midnight":
            return .solarMidnight
        default:
            return .color(item.calendarColor)
        }
    }

    func backgroundTintColor(for item: UpcomingItem, now: Date) -> NSColor {
        if item.showsMutedBackground {
            return item.calendarColor.withAlphaComponent(0.26)
        }
        if item.kind == .reminder, item.date <= now {
            return item.calendarColor.withAlphaComponent(0.26)
        }
        return .clear
    }

    func segmentBackgroundVisual(for item: UpcomingItem, now: Date, settings: SettingsSnapshot) -> (color: NSColor, progress: CGFloat) {
        if let progress = activeEventProgress(for: item, now: now, settings: settings) {
            return (item.calendarColor.withAlphaComponent(0.30), progress)
        }

        let fullTint = backgroundTintColor(for: item, now: now)
        if fullTint.alphaComponent > 0.01 {
            return (fullTint, 1.0)
        }

        return (.clear, 0)
    }

    func activeEventProgress(for item: UpcomingItem, now: Date, settings: SettingsSnapshot) -> CGFloat? {
        guard item.kind == .event || item.kind == .weather else { return nil }
        guard let endDate = item.endDate, endDate > item.date else { return nil }
        guard item.date <= now, now < endDate else { return nil }

        let totalDuration: TimeInterval
        let elapsed: TimeInterval
        if item.kind == .event,
           let calendarID = item.calendarID,
           settings.weekdayOnlyEventCalendarIDs.contains(calendarID) {
            totalDuration = weekdayOnlyDuration(from: item.date, to: endDate)
            elapsed = weekdayOnlyDuration(from: item.date, to: now)
        } else {
            totalDuration = endDate.timeIntervalSince(item.date)
            elapsed = now.timeIntervalSince(item.date)
        }
        guard totalDuration > 0 else { return nil }

        return min(max(CGFloat(elapsed / totalDuration), 0), 1)
    }

    private func weekdayOnlyDuration(from start: Date, to end: Date) -> TimeInterval {
        guard end > start else { return 0 }
        let calendar = Calendar.current
        var cursor = start
        var total: TimeInterval = 0

        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let segmentEnd = min(end, nextDayStart)
            if isWeekday(dayStart) {
                total += segmentEnd.timeIntervalSince(cursor)
            }
            cursor = segmentEnd
        }

        return total
    }
    func allDayLabel(for item: UpcomingItem) -> String? {
        guard item.kind == .event, item.isAllDay else { return nil }
        guard let endDate = item.endDate else { return "all-day" }

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: item.date)
        let endDay = calendar.startOfDay(for: endDate)
        let usesExclusiveEndDay = endDate == endDay
        let lastInclusiveDay: Date
        if usesExclusiveEndDay,
           let adjusted = calendar.date(byAdding: .day, value: -1, to: endDay) {
            lastInclusiveDay = adjusted
        } else {
            lastInclusiveDay = endDay
        }

        let daySpan = calendar.dateComponents([.day], from: startDay, to: lastInclusiveDay).day ?? 0
        guard daySpan >= 1 else { return "all-day" }

        let sameMonth = calendar.isDate(startDay, equalTo: lastInclusiveDay, toGranularity: .month)
            && calendar.isDate(startDay, equalTo: lastInclusiveDay, toGranularity: .year)
        if sameMonth {
            let monthText = Self.allDayMonthFormatter.string(from: startDay)
            let startDayNumber = calendar.component(.day, from: startDay)
            let endDayNumber = calendar.component(.day, from: lastInclusiveDay)
            return "\(monthText) \(startDayNumber)-\(endDayNumber)"
        }

        let startText = Self.allDayDateFormatter.string(from: startDay)
        let endText = Self.allDayDateFormatter.string(from: lastInclusiveDay)
        return "\(startText)-\(endText)"
    }

    func color(from calendar: EKCalendar) -> NSColor {
        if let converted = NSColor(cgColor: calendar.cgColor) {
            return converted
        }
        return .systemBlue
    }

    func trimmedTitle(_ title: String, maxLength: Int) -> String {
        guard title.count > maxLength else { return title }
        let end = title.index(title.startIndex, offsetBy: maxLength - 1)
        return String(title[..<end])
    }

    func relativeCountdown(to targetDate: Date, from sourceDate: Date, simplified: Bool) -> String {
        let remaining = max(Int(targetDate.timeIntervalSince(sourceDate)), 0)
        if remaining < 60 {
            return "\(remaining)s"
        }
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if simplified {
            if days > 0 {
                return "\(days)d"
            }
            if hours > 0 {
                return "\(hours)h"
            }
            return "\(minutes)m"
        }

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    func elapsedCountdown(from startDate: Date, to endDate: Date, simplified: Bool) -> String {
        let elapsed = max(Int(endDate.timeIntervalSince(startDate)), 0)
        if elapsed < 60 {
            return "\(elapsed)s"
        }
        let days = elapsed / 86_400
        let hours = (elapsed % 86_400) / 3_600
        let minutes = (elapsed % 3_600) / 60

        if simplified {
            if days > 0 {
                return "\(days)d"
            }
            if hours > 0 {
                return "\(hours)h"
            }
            return "\(minutes)m"
        }

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
