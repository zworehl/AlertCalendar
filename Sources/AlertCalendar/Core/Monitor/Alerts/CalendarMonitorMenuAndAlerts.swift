import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    nonisolated static func formattedAllDayRange(
        startDay: Date,
        lastInclusiveDay: Date,
        calendar: Calendar = .current,
        locale: Locale? = nil
    ) -> String {
        AlertCalendarDateRangeFormatter.compactAllDayRange(
            startDay: startDay,
            lastInclusiveDay: lastInclusiveDay,
            calendar: calendar,
            locale: locale ?? .autoupdatingCurrent
        )
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
        let shouldAnimateAlert = state.alertedSegmentIndex != nil && currentSettings.enableBlinkAlert
        let previousAlertedSegmentIndex = combinedMenuBarAlertedSegmentIndex

        setIfChanged(\.combinedMenuBarLabel, to: state.label)
        setColorIfChanged(\.combinedMenuBarColor, to: state.color)
        setIfChanged(\.combinedMenuBarAlertedSegmentIndex, to: state.alertedSegmentIndex)
        if !shouldAnimateAlert || previousAlertedSegmentIndex != state.alertedSegmentIndex || menuBarAnimationCancellable == nil {
            setIfChanged(\.combinedMenuBarAlertTextOpacity, to: state.alertTextOpacity)
        }
        setColorArrayIfChanged(\.combinedMenuBarDotColors, to: state.dotColors)
        setIfChanged(\.combinedMenuBarMarkerStyles, to: state.markerStyles)
        setIfChanged(\.combinedMenuBarSegments, to: state.segments)
        setColorArrayIfChanged(\.combinedMenuBarSegmentBackgroundColors, to: state.segmentBackgroundColors)
        setIfChanged(\.combinedMenuBarSegmentBackgroundProgresses, to: state.segmentBackgroundProgresses)
        setIfChanged(\.combinedMenuBarSegmentParticipationStatuses, to: state.segmentParticipationStatuses)
        setIfChanged(\.combinedMenuBarSegmentTextureStatuses, to: state.segmentTextureStatuses)
        setIfChanged(\.combinedMenuBarSegmentAccessorySymbolNames, to: state.segmentAccessorySymbolNames)
        setIfChanged(\.combinedMenuBarFootballDisplay, to: state.footballDisplay)
        setIfChanged(\.combinedMenuBarFootballTrailingText, to: state.footballTrailingText)
        setIfChanged(\.combinedMenuBarFootballStatusText, to: state.footballStatusText)
        setColorIfChanged(\.combinedMenuBarFootballStatusColor, to: state.footballStatusColor)
        setIfChanged(\.combinedMenuBarFootballGoalHighlightSide, to: state.footballGoalHighlightSide)
        setIfChanged(\.combinedMenuBarFootballGoalHighlightTextOpacity, to: state.footballGoalHighlightTextOpacity)
        setMenuBarAlertAnimationEnabled(shouldAnimateAlert)

        var publishedState = state
        publishedState.alertTextOpacity = combinedMenuBarAlertTextOpacity
        menuBarPresentationModel.apply(publishedState)
    }

    nonisolated static let alertBlinkPeriod: TimeInterval = 2

    nonisolated static func alertBlinkTextOpacity(now: Date) -> CGFloat {
        let remainder = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: alertBlinkPeriod)
        let normalizedRemainder = remainder < 0 ? remainder + alertBlinkPeriod : remainder
        let phase = normalizedRemainder / alertBlinkPeriod
        return CGFloat((cos(phase * 2 * .pi) + 1) / 2)
    }

    nonisolated static func shouldAlertForItem(_ item: UpcomingItem, now: Date, leadSeconds: TimeInterval) -> Bool {
        let remaining = item.date.timeIntervalSince(now)
        if remaining > 0 && remaining <= leadSeconds {
            return true
        }

        return shouldShowTimedEventNowState(for: item, now: now)
    }

    nonisolated static func shouldBlinkOverdueTimedEvent(_ item: UpcomingItem, now: Date) -> Bool {
        item.kind == .event
            && !item.isAllDay
            && item.date < now
    }

    nonisolated static func shouldAlertForItem(_ item: UpcomingItem, now: Date, settings: AppSettings) -> Bool {
        guard AstronomyMoment(eventTitle: item.title) == nil else { return false }

        let leadSeconds = TimeInterval(max(1, settings.alertLeadMinutes) * 60)
        return shouldAlertForItem(item, now: now, leadSeconds: leadSeconds)
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
        guard let candidate = upcomingItems.first(where: {
            Self.shouldAlertForItem($0, now: now, settings: settings)
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
        let menuBarQueue = unifiedMenuBarQueue(now: now, settings: settings)
        let queueMatchIDs = Set(menuBarQueue.compactMap { $0.footballMatch?.id })
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
                    eventTitleMaxCharacters: settings.eventTitleMaxCharacters,
                    rewrittenTitle: rewrittenEventTitle(for: $0, settings: settings)
                )
            }
            let alertedSegmentIndex: Int?
            let alertTextOpacity: CGFloat
            let activeAlertIndex = activeAlertItem.flatMap { activeAlertItem in
                previewItems.firstIndex(where: { $0.notificationKey == activeAlertItem.notificationKey })
            }
            let overdueEventIndex = previewItems.firstIndex(where: {
                Self.shouldBlinkOverdueTimedEvent($0, now: now)
            })
            if settings.enableBlinkAlert,
               let blinkingIndex = activeAlertIndex ?? overdueEventIndex {
                alertedSegmentIndex = blinkingIndex
                alertTextOpacity = Self.alertBlinkTextOpacity(now: now)
            } else {
                alertedSegmentIndex = nil
                alertTextOpacity = 0
            }
            let selectedItem = previewItems.first
            let showsFootballMenuBarDetails = Self.shouldShowFootballMenuBarDetails(
                for: selectedItem,
                in: menuBarQueue
            )
            let footballStatusText = Self.shouldShowFootballMenuBarStatus(for: selectedItem)
                ? selectedItem.flatMap { footballMenuBarStatusText(for: $0, now: now) }
                : nil
            let footballStatusColor = footballStatusText.map(Self.footballStatusTintColor(for:)) ?? .systemGreen

            let footballGoalHighlightSide: FootballScoreSide?
            let footballGoalHighlightTextOpacity: CGFloat
            if showsFootballMenuBarDetails,
               let highlight = activeFootballGoalHighlight,
               selectedItem?.footballMatch?.id == highlight.matchID {
                footballGoalHighlightSide = highlight.scoringSide
                footballGoalHighlightTextOpacity = Int(now.timeIntervalSinceReferenceDate).isMultiple(of: 2)
                    ? 1.0
                    : 0.0
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
                    markerStyles: previewItems.map { markerStyle(for: $0, now: now) },
                    segments: segments,
                    segmentBackgroundColors: segmentBackgrounds.map(\.color),
                    segmentBackgroundProgresses: segmentBackgrounds.map(\.progress),
                    segmentParticipationStatuses: previewItems.map(\.eventParticipationStatus),
                    segmentTextureStatuses: previewItems.map {
                        activeParticipationTextureStatus(for: $0, now: now, settings: settings)
                    },
                    segmentAccessorySymbolNames: previewItems.map(menuBarAccessorySymbolNames(for:)),
                    footballDisplay: showsFootballMenuBarDetails ? selectedItem?.footballMenuBarDisplay : nil,
                    footballTrailingText: showsFootballMenuBarDetails
                        ? selectedItem.flatMap {
                            footballMenuBarTrailingText(
                                for: $0,
                                now: now,
                                simplified: settings.useSimplifiedCountdown
                            )
                        }
                        : nil,
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
            rewrittenTitle: nextEvent.flatMap { rewrittenEventTitle(for: $0, settings: settings) },
            fallback: "No events"
        ))

        setIfChanged(\.remindersMenuBarLabel, to: menuLabel(
            for: nextReminder,
            now: now,
            simplified: settings.useSimplifiedCountdown,
            activeEventDisplayMode: settings.activeEventDisplayMode,
            useEventTitleEllipsis: settings.useEventTitleEllipsis,
            eventTitleMaxCharacters: settings.eventTitleMaxCharacters,
            rewrittenTitle: nextReminder.flatMap { rewrittenEventTitle(for: $0, settings: settings) },
            fallback: "No reminders"
        ))
    }

    func applyMenuBarLoadingState() {
        applyMenuBarPresentationState(.loading)
    }


}
