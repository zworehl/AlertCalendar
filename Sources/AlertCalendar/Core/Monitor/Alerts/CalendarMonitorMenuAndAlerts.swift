import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    static let allDayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    static let allDayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

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

    func evaluateAlert(now: Date, settings: AppSettings) {
        let leadSeconds = TimeInterval(max(1, settings.alertLeadMinutes) * 60)
        guard let candidate = upcomingItems.first(where: {
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
            setIfChanged(\.combinedMenuBarLabel, to: emptyStateText)
            setColorIfChanged(\.combinedMenuBarColor, to: .systemGray)
            setIfChanged(\.combinedMenuBarAlertedSegmentIndex, to: nil)
            setIfChanged(\.combinedMenuBarAlertTextOpacity, to: 0)
            setColorArrayIfChanged(\.combinedMenuBarDotColors, to: [.systemGray])
            setIfChanged(\.combinedMenuBarMarkerStyles, to: [.color(.systemGray)])
            setIfChanged(\.combinedMenuBarSegments, to: [emptyStateText])
            setColorArrayIfChanged(\.combinedMenuBarSegmentBackgroundColors, to: [.clear])
            setIfChanged(\.combinedMenuBarSegmentBackgroundProgresses, to: [0])
            setIfChanged(\.combinedMenuBarFootballDisplay, to: nil)
            setIfChanged(\.combinedMenuBarFootballTrailingText, to: nil)
            setIfChanged(\.combinedMenuBarFootballStatusText, to: nil)
            setColorIfChanged(\.combinedMenuBarFootballStatusColor, to: .systemGreen)
            setIfChanged(\.combinedMenuBarFootballGoalHighlightSide, to: nil)
            setIfChanged(\.combinedMenuBarFootballGoalHighlightTextOpacity, to: 0)
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
            setIfChanged(\.combinedMenuBarFootballDisplay, to: previewItems.first?.footballMenuBarDisplay)
            setIfChanged(
                \.combinedMenuBarFootballTrailingText,
                to: previewItems.first.flatMap {
                    footballMenuBarTrailingText(
                        for: $0,
                        now: now,
                        simplified: settings.useSimplifiedCountdown
                    )
                }
            )
            let footballStatusText = previewItems.first.flatMap { footballMenuBarStatusText(for: $0, now: now) }
            setIfChanged(\.combinedMenuBarFootballStatusText, to: footballStatusText)
            setColorIfChanged(
                \.combinedMenuBarFootballStatusColor,
                to: footballStatusText.map(Self.footballStatusTintColor(for:)) ?? .systemGreen
            )

            if let highlight = activeFootballGoalHighlight,
               previewItems.first?.footballMatch?.id == highlight.matchID {
                setIfChanged(\.combinedMenuBarFootballGoalHighlightSide, to: highlight.scoringSide)
                setIfChanged(\.combinedMenuBarFootballGoalHighlightTextOpacity, to: tickCount.isMultiple(of: 2) ? 1.0 : 0.0)
            } else {
                setIfChanged(\.combinedMenuBarFootballGoalHighlightSide, to: nil)
                setIfChanged(\.combinedMenuBarFootballGoalHighlightTextOpacity, to: 0)
            }
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

    func applyMenuBarLoadingState() {
        setIfChanged(\.combinedMenuBarLabel, to: "Loading...")
        setColorIfChanged(\.combinedMenuBarColor, to: .systemGray)
        setIfChanged(\.combinedMenuBarAlertedSegmentIndex, to: nil)
        setIfChanged(\.combinedMenuBarAlertTextOpacity, to: 0)
        setColorArrayIfChanged(\.combinedMenuBarDotColors, to: [.systemGray])
        setIfChanged(\.combinedMenuBarMarkerStyles, to: [.color(.systemGray)])
        setIfChanged(\.combinedMenuBarSegments, to: ["Loading..."])
        setColorArrayIfChanged(\.combinedMenuBarSegmentBackgroundColors, to: [.clear])
        setIfChanged(\.combinedMenuBarSegmentBackgroundProgresses, to: [0])
        setIfChanged(\.combinedMenuBarFootballDisplay, to: nil)
        setIfChanged(\.combinedMenuBarFootballTrailingText, to: nil)
        setIfChanged(\.combinedMenuBarFootballStatusText, to: nil)
        setColorIfChanged(\.combinedMenuBarFootballStatusColor, to: .systemGreen)
        setIfChanged(\.combinedMenuBarFootballGoalHighlightSide, to: nil)
        setIfChanged(\.combinedMenuBarFootballGoalHighlightTextOpacity, to: 0)
    }


}
