import Foundation

extension CalendarMonitor {
    nonisolated private static let eventTitleRewriteRetryIntervals: [TimeInterval] = [
        10,
        30,
        60,
        5 * 60,
    ]

    nonisolated static func eventTitleRewriteRetryDelay(forAttempt attempt: Int) -> TimeInterval {
        let index = min(max(0, attempt), eventTitleRewriteRetryIntervals.count - 1)
        return eventTitleRewriteRetryIntervals[index]
    }

    func scheduleEventTitleRewritesIfNeeded(now: Date, settings: AppSettings) {
        guard settings.useEventTitleEllipsis,
              settings.rewriteEventTitlesWithAppleIntelligence,
              AppSettingsRules.allowsAppleIntelligenceTitleRewrite(
                maximumCharacters: settings.eventTitleMaxCharacters
              ) else {
            cancelEventTitleRewrites(clearDisplayedTitles: true)
            return
        }

        let maximumCharacters = AppSettingsRules.normalizedEventTitleMaxCharacters(
            settings.eventTitleMaxCharacters
        )
        let menuBarCandidates = unifiedMenuBarQueue(now: now, settings: settings)
        let candidates: [UpcomingItem]
        if settings.useRewrittenEventTitlesInDropdown {
            let dropdownFutureWindowEnd = now.addingTimeInterval(Double(max(1, settings.lookAheadHours)) * 3600)
            let dropdownCandidates = deduplicatedItemsByNotificationKey(
                (allDayEventItems + upcomingItems)
                    .filter {
                        Self.shouldIncludeInDropdownPreviewWindow(
                            $0,
                            now: now,
                            futureWindowEnd: dropdownFutureWindowEnd
                        )
                    }
                    .sorted { left, right in
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
            )
            let visibleDropdownCandidates = Array(dropdownCandidates.prefix(max(1, settings.maxListItems)))
            candidates = Array(
                deduplicatedItemsByNotificationKey(menuBarCandidates + visibleDropdownCandidates)
            )
        } else {
            candidates = menuBarCandidates
        }

        let eligibleCandidates = candidates
            .filter {
                EventTitleRewriteResolver.shouldRequestRewrite(
                    for: $0.title,
                    maximumCharacters: maximumCharacters
                )
                    && $0.footballMatch == nil
                    && !isBirthdayItem($0)
                    && EventBirthdayTitle.parse($0.title) == nil
                    && AstronomyMoment(eventTitle: $0.title) == nil
            }
            .sorted { left, right in
                if left.isAllDay != right.isAllDay {
                    return !left.isAllDay
                }
                if left.date != right.date {
                    return left.date < right.date
                }
                return left.notificationKey < right.notificationKey
            }
        let fingerprint = makeEventTitleRewriteFingerprint(
            candidates: eligibleCandidates,
            maximumCharacters: maximumCharacters,
            includesDropdown: settings.useRewrittenEventTitlesInDropdown,
            usesMailContext: settings.useMailContextForEventTitleRewrite
        )
        let eligibleKeys = Set(eligibleCandidates.map(\.notificationKey))
        rewrittenEventTitlesByItemKey = rewrittenEventTitlesByItemKey.filter {
            eligibleKeys.contains($0.key)
        }
        guard !eligibleCandidates.isEmpty else {
            eventTitleRewriteTask?.cancel()
            eventTitleRewriteTask = nil
            eventTitleRewriteFingerprint = fingerprint
            resetEventTitleRewriteRetryState()
            return
        }

        eventTitleRewriteRetryTask?.cancel()
        eventTitleRewriteRetryTask = nil
        guard eventTitleRewriteFingerprint != fingerprint else { return }

        eventTitleRewriteTask?.cancel()
        eventTitleRewriteFingerprint = fingerprint

        let attachmentPreviewProvider = agendaSummaryAttachmentPreviewProvider
        let mailContextProvider = eventMailContextProvider
        let usesMailContext = settings.useMailContextForEventTitleRewrite
        eventTitleRewriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var encounteredFailure = false

            for item in eligibleCandidates {
                guard !Task.isCancelled else { return }
                let itemKey = item.notificationKey
                let mailContexts: [String]
                if usesMailContext, item.kind == .event {
                    mailContexts = await mailContextProvider.contexts(
                        for: EventMailContextRequest(
                            title: item.title,
                            description: item.descriptionText,
                            participantEmailAddresses: (
                                [item.organizer?.emailAddress]
                                    + item.attendees.map(\.emailAddress)
                            ).compactMap { $0 }
                        )
                    )
                } else {
                    mailContexts = []
                }
                guard !Task.isCancelled else { return }
                let sourceFingerprint = EventTitleRewriteSourceFingerprint.make(
                    for: item,
                    mailContexts: mailContexts
                )
                if !persistentEventTitleRewriteCache.hasMatchingSource(
                    for: itemKey,
                    sourceFingerprint: sourceFingerprint
                ) {
                    rewrittenEventTitlesByItemKey.removeValue(forKey: itemKey)
                }
                if let cachedTitle = persistentEventTitleRewriteCache.reusableTitle(
                    for: itemKey,
                    sourceFingerprint: sourceFingerprint,
                    maximumCharacters: maximumCharacters,
                    now: fixedSecondNow(),
                    originalTitle: item.title
                ) {
                    rewrittenEventTitlesByItemKey[itemKey] = cachedTitle
                    eventTitleRewriteCacheStore?.save(persistentEventTitleRewriteCache)
                    updateMenuBarState(now: fixedSecondNow(), settings: snapshotSettings())
                    continue
                }
                guard eventTitleRewriter.availability.isAvailable else {
                    encounteredFailure = true
                    continue
                }

                let attachmentPreviews = await attachmentPreviewProvider.contexts(
                    for: AttachmentContextRequest(
                        references: item.agendaSummaryAttachments,
                        referenceText: [
                            item.title,
                            item.descriptionText,
                            item.locationText,
                            item.calendarName,
                            item.organizer?.displayText,
                        ].compactMap { $0 }
                            + item.attendees.map(\.displayText)
                            + item.urlHosts,
                        maximumCharactersPerAttachment: 2_400,
                        maximumTotalCharacters: 7_200,
                        maximumContexts: 6
                    )
                )
                guard !Task.isCancelled else { return }
                let request = EventTitleRewriteRequest(
                    title: item.title,
                    description: item.descriptionText,
                    urlHosts: item.urlHosts,
                    hasMeetingURL: item.meetingURL != nil,
                    attachmentNames: item.agendaSummaryAttachments.map(\.fileName),
                    attachmentPreviews: attachmentPreviews,
                    mailContexts: mailContexts,
                    itemKind: item.kind.rawValue,
                    startsAt: item.date,
                    endsAt: item.endDate,
                    timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
                    isAllDay: item.isAllDay,
                    location: item.locationText,
                    calendarName: item.calendarName,
                    isRecurring: item.isRecurring,
                    organizerName: item.organizer?.displayText,
                    attendeeNames: item.attendees.map(\.displayText),
                    maximumCharacters: maximumCharacters
                )
                let rewrittenTitle: String
                do {
                    let generatedTitle = try await eventTitleRewriter.rewriteTitle(for: request)
                    try Task.checkCancellation()
                    rewrittenTitle = EventTitleRewriteResolver.resolvedTitle(
                        generatedTitle,
                        request: request
                    )
                    persistentEventTitleRewriteCache.record(
                        title: rewrittenTitle,
                        for: itemKey,
                        sourceFingerprint: sourceFingerprint,
                        maximumCharacters: maximumCharacters,
                        now: fixedSecondNow()
                    )
                    eventTitleRewriteCacheStore?.save(persistentEventTitleRewriteCache)
                } catch is CancellationError {
                    return
                } catch {
                    encounteredFailure = true
                    CalendarMonitorLog.titleRewrite.error(
                        "Could not rewrite a calendar title: \(String(describing: error), privacy: .public)"
                    )
                    continue
                }

                rewrittenEventTitlesByItemKey[itemKey] = rewrittenTitle
                updateMenuBarState(now: fixedSecondNow(), settings: snapshotSettings())
            }

            guard eventTitleRewriteFingerprint == fingerprint else { return }
            eventTitleRewriteTask = nil
            dataRefreshHealthState.titleRewriteError = encounteredFailure
                ? "Apple Intelligence could not update some event titles. The original titles remain available." : nil
            if encounteredFailure {
                eventTitleRewriteFingerprint = nil
                scheduleEventTitleRewriteRetry()
            } else {
                resetEventTitleRewriteRetryState()
            }
        }
    }

    func eventTitle(for item: UpcomingItem, inDropdown: Bool) -> String {
        let settings = currentSettings
        guard !inDropdown || settings.useRewrittenEventTitlesInDropdown else {
            return item.title
        }
        let presentation = eventTitlePresentation(for: item, settings: settings)
        if inDropdown, settings.useEventTitleEllipsis, !presentation.usesResolvedTitle {
            return trimmedTitle(presentation.title, maxLength: settings.eventTitleMaxCharacters)
        }
        return presentation.title
    }

    func eventTitlePresentation(
        for item: UpcomingItem,
        settings: AppSettings
    ) -> EventTitlePresentation {
        EventTitlePresentationResolver.resolve(
            originalTitle: item.title,
            rewrittenTitle: rewrittenEventTitlesByItemKey[item.notificationKey],
            maximumCharacters: settings.eventTitleMaxCharacters,
            isEnabled: settings.useEventTitleEllipsis && item.footballMatch == nil
                && AstronomyMoment(eventTitle: item.title) == nil,
            isBirthday: isBirthdayItem(item),
            usesModelRewrite: settings.rewriteEventTitlesWithAppleIntelligence,
            otherBirthdayNames: (allDayEventItems + upcomingItems)
                .filter { $0.notificationKey != item.notificationKey && isBirthdayItem($0) }
                .compactMap { EventBirthdayTitle.parse($0.title, knownBirthday: true)?.name }
        )
    }

    private func cancelEventTitleRewrites(clearDisplayedTitles: Bool) {
        eventTitleRewriteTask?.cancel()
        eventTitleRewriteTask = nil
        resetEventTitleRewriteRetryState()
        eventTitleRewriteFingerprint = nil
        if clearDisplayedTitles, !rewrittenEventTitlesByItemKey.isEmpty {
            rewrittenEventTitlesByItemKey = [:]
        }
    }

    private func scheduleEventTitleRewriteRetry() {
        guard eventTitleRewriteRetryTask == nil else { return }
        let attempt = eventTitleRewriteRetryAttempt
        let delay = Self.eventTitleRewriteRetryDelay(forAttempt: attempt)
        eventTitleRewriteRetryAttempt = attempt + 1
        eventTitleRewriteRetryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: CalendarMonitorTime.nanoseconds(forDelay: delay)
                )
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.eventTitleRewriteRetryTask = nil
            self.eventTitleRewriteFingerprint = nil
            self.scheduleEventTitleRewritesIfNeeded(
                now: self.fixedSecondNow(),
                settings: self.snapshotSettings()
            )
        }
    }

    private func resetEventTitleRewriteRetryState() {
        eventTitleRewriteRetryTask?.cancel()
        eventTitleRewriteRetryTask = nil
        eventTitleRewriteRetryAttempt = 0
    }

    private func makeEventTitleRewriteFingerprint(
        candidates: [UpcomingItem],
        maximumCharacters: Int,
        includesDropdown: Bool,
        usesMailContext: Bool
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(maximumCharacters)
        hasher.combine(includesDropdown)
        hasher.combine(usesMailContext)
        if usesMailContext {
            hasher.combine(AppleMailAutomationPermission.currentStatus())
        }
        for item in candidates {
            hasher.combine(item.notificationKey)
            hasher.combine(EventTitleRewriteSourceFingerprint.make(for: item))
        }
        return hasher.finalize()
    }
}
