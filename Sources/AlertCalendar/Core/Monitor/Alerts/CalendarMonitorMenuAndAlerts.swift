import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    nonisolated static func makeAllDayDateFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "MMM d"
        return formatter
    }

    nonisolated static func makeAllDayMonthFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "MMM"
        return formatter
    }

    nonisolated static let allDayDateFormatter: DateFormatter = {
        makeAllDayDateFormatter(locale: .autoupdatingCurrent)
    }()

    nonisolated static let allDayMonthFormatter: DateFormatter = {
        makeAllDayMonthFormatter(locale: .autoupdatingCurrent)
    }()

    nonisolated static func formattedAllDayRange(
        startDay: Date,
        lastInclusiveDay: Date,
        calendar: Calendar = .current,
        locale: Locale? = nil
    ) -> String {
        let dateFormatter = locale.map(makeAllDayDateFormatter(locale:)) ?? allDayDateFormatter
        let monthFormatter = locale.map(makeAllDayMonthFormatter(locale:)) ?? allDayMonthFormatter

        let sameMonth = calendar.isDate(startDay, equalTo: lastInclusiveDay, toGranularity: .month)
            && calendar.isDate(startDay, equalTo: lastInclusiveDay, toGranularity: .year)
        if sameMonth {
            let monthText = monthFormatter.string(from: startDay)
            let startDayNumber = calendar.component(.day, from: startDay)
            let endDayNumber = calendar.component(.day, from: lastInclusiveDay)
            return "\(monthText) \(startDayNumber)-\(endDayNumber)"
        }

        let startText = dateFormatter.string(from: startDay)
        let endText = dateFormatter.string(from: lastInclusiveDay)
        return "\(startText)-\(endText)"
    }

    func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<CalendarMonitor, T>, to newValue: T) {
        if self[keyPath: keyPath] != newValue {
            self[keyPath: keyPath] = newValue
        }
    }

    func setColorIfChanged(_ keyPath: ReferenceWritableKeyPath<CalendarMonitor, NSColor>, to newValue: NSColor) {
        let current = self[keyPath: keyPath]
        if !current.isEqual(newValue) {
            self[keyPath: keyPath] = newValue
        }
    }

    func setColorArrayIfChanged(_ keyPath: ReferenceWritableKeyPath<CalendarMonitor, [NSColor]>, to newValue: [NSColor]) {
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

    func applyMenuBarPresentationState(_ state: MenuBarPresentationState) {
        setIfChanged(\.combinedMenuBarLabel, to: state.label)
        setColorIfChanged(\.combinedMenuBarColor, to: state.color)
        setIfChanged(\.combinedMenuBarAlertedSegmentIndex, to: state.alertedSegmentIndex)
        setIfChanged(\.combinedMenuBarAlertTextOpacity, to: state.alertTextOpacity)
        setColorArrayIfChanged(\.combinedMenuBarDotColors, to: state.dotColors)
        setIfChanged(\.combinedMenuBarMarkerStyles, to: state.markerStyles)
        setIfChanged(\.combinedMenuBarSegments, to: state.segments)
        setColorArrayIfChanged(\.combinedMenuBarSegmentBackgroundColors, to: state.segmentBackgroundColors)
        setIfChanged(\.combinedMenuBarSegmentBackgroundProgresses, to: state.segmentBackgroundProgresses)
        setIfChanged(\.combinedMenuBarFootballDisplay, to: state.footballDisplay)
        setIfChanged(\.combinedMenuBarFootballTrailingText, to: state.footballTrailingText)
        setIfChanged(\.combinedMenuBarFootballStatusText, to: state.footballStatusText)
        setColorIfChanged(\.combinedMenuBarFootballStatusColor, to: state.footballStatusColor)
        setIfChanged(\.combinedMenuBarFootballGoalHighlightSide, to: state.footballGoalHighlightSide)
        setIfChanged(\.combinedMenuBarFootballGoalHighlightTextOpacity, to: state.footballGoalHighlightTextOpacity)
    }

    nonisolated static func alertBlinkTextOpacity(now: Date) -> CGFloat {
        let wholeSecond = Int(now.timeIntervalSince1970.rounded(.down))
        return wholeSecond.isMultiple(of: 2) ? 1.0 : 0.0
    }

    nonisolated static func shouldAlertForItem(_ item: UpcomingItem, now: Date, leadSeconds: TimeInterval) -> Bool {
        let remaining = item.date.timeIntervalSince(now)
        if remaining > 0 && remaining <= leadSeconds {
            return true
        }

        return shouldShowTimedEventNowState(for: item, now: now)
    }

    nonisolated static func alertDescription(for item: UpcomingItem, now: Date) -> String {
        if shouldShowTimedEventNowState(for: item, now: now) {
            return "\(item.title) starts now."
        }

        return AlertCalendarRelativeTimeFormatter.leadTimeDescription(
            for: item.title,
            targetDate: item.date,
            now: now
        )
    }

    func evaluateAlert(now: Date, settings: AppSettings) {
        let leadSeconds = TimeInterval(max(1, settings.alertLeadMinutes) * 60)
        guard let candidate = upcomingItems.first(where: {
            guard AstronomyMoment(eventTitle: $0.title) == nil else { return false }
            return Self.shouldAlertForItem($0, now: now, leadSeconds: leadSeconds)
        }) else {
            setIfChanged(\.activeAlertItem, to: nil)
            return
        }

        if silencedAlertKeys.contains(candidate.notificationKey) {
            setIfChanged(\.activeAlertItem, to: nil)
            return
        }

        setIfChanged(\.activeAlertItem, to: candidate)

        if candidate.date > now, !alreadyNotified.contains(candidate.notificationKey) {
            alreadyNotified.insert(candidate.notificationKey)
            triggerLocalBeep()
        }
    }

    func triggerLocalBeep() {
        AlertCalendarSoundPlayer.beep()
    }

    func pruneAlertCaches(using items: [UpcomingItem]) {
        let validKeys = Set(items.map(\.notificationKey))
        alreadyNotified.formIntersection(validKeys)
        silencedAlertKeys.formIntersection(validKeys)
    }

    func updateMenuBarState(now: Date, settings: AppSettings) {
        if isInitialLoadInProgress {
            applyMenuBarLoadingState()
            return
        }

        let previewItems = displayedItemsForMenuBar(now: now, settings: settings)
        let queueMatchIDs = Set(
            unifiedMenuBarQueue(now: now, settings: settings)
                .compactMap { $0.footballMatch?.id }
        )
        activeFootballGoalHighlight = Self.updatedFootballGoalHighlight(
            activeFootballGoalHighlight,
            queueMatchIDs: queueMatchIDs,
            selectedMatchID: previewItems.first?.footballMatch?.id
        )
        if previewItems.isEmpty {
            let emptyStateText = Self.menuBarEmptyStateText(
                menuBarRotationWindowMinutes: settings.menuBarRotationWindowMinutes,
                hasLaterItemsInDropdownWindow: hasUpcomingItemsOutsideMenuBarWindow(now: now, settings: settings)
            )
            applyMenuBarPresentationState(.empty(text: emptyStateText))
        } else {
            let segmentBackgrounds = previewItems.map { segmentBackgroundVisual(for: $0, now: now, settings: settings) }
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
            let alertedSegmentIndex: Int?
            let alertTextOpacity: CGFloat
            if settings.enableBlinkAlert,
               let activeAlertItem,
               let alertIndex = previewItems.firstIndex(where: { $0.notificationKey == activeAlertItem.notificationKey }) {
                alertedSegmentIndex = alertIndex
                alertTextOpacity = Self.alertBlinkTextOpacity(now: now)
            } else {
                alertedSegmentIndex = nil
                alertTextOpacity = 0
            }
            let footballStatusText = previewItems.first.flatMap { footballMenuBarStatusText(for: $0, now: now) }
            let footballStatusColor = footballStatusText.map(Self.footballStatusTintColor(for:)) ?? .systemGreen

            let footballGoalHighlightSide: FootballScoreSide?
            let footballGoalHighlightTextOpacity: CGFloat
            if let highlight = activeFootballGoalHighlight,
               previewItems.first?.footballMatch?.id == highlight.matchID {
                footballGoalHighlightSide = highlight.scoringSide
                footballGoalHighlightTextOpacity = tickCount.isMultiple(of: 2) ? 1.0 : 0.0
            } else {
                footballGoalHighlightSide = nil
                footballGoalHighlightTextOpacity = 0
            }

            applyMenuBarPresentationState(
                MenuBarPresentationState(
                    label: segments.joined(separator: "  "),
                    color: previewItems[0].calendarColor.nsColor,
                    alertedSegmentIndex: alertedSegmentIndex,
                    alertTextOpacity: alertTextOpacity,
                    dotColors: previewItems.map { $0.calendarColor.nsColor },
                    markerStyles: previewItems.map { markerStyle(for: $0) },
                    segments: segments,
                    segmentBackgroundColors: segmentBackgrounds.map(\.color),
                    segmentBackgroundProgresses: segmentBackgrounds.map(\.progress),
                    footballDisplay: previewItems.first?.footballMenuBarDisplay,
                    footballTrailingText: previewItems.first.flatMap {
                        footballMenuBarTrailingText(
                            for: $0,
                            now: now,
                            simplified: settings.useSimplifiedCountdown
                        )
                    },
                    footballStatusText: footballStatusText,
                    footballStatusColor: footballStatusColor,
                    footballGoalHighlightSide: footballGoalHighlightSide,
                    footballGoalHighlightTextOpacity: footballGoalHighlightTextOpacity
                )
            )
        }

        let nextEvent = rotatingTimedItem(now: now, settings: settings)
        let nextReminder = rotatingReminderItem(now: now, settings: settings)

        setColorIfChanged(\.eventsMenuBarColor, to: nextEvent?.calendarColor.nsColor ?? .systemGray)
        setColorIfChanged(\.remindersMenuBarColor, to: nextReminder?.calendarColor.nsColor ?? .systemGray)

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

    func applyMenuBarLoadingState() {
        applyMenuBarPresentationState(.loading)
    }


}
