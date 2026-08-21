import Foundation

struct EventTitleRewriteCacheKey: Hashable {
    let title: String
    let maximumCharacters: Int
}

extension CalendarMonitor {
    func scheduleEventTitleRewritesIfNeeded(now: Date, settings: AppSettings) {
        guard settings.useEventTitleEllipsis,
              settings.rewriteEventTitlesWithAppleIntelligence,
              AppSettingsRules.allowsAppleIntelligenceTitleRewrite(
                maximumCharacters: settings.eventTitleMaxCharacters
              ),
              eventTitleRewriter.availability.isAvailable else {
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

        let eligibleCandidates = candidates.filter {
            EventTitleRewriteResolver.shouldRequestRewrite(
                for: $0.title,
                maximumCharacters: maximumCharacters
            )
                && $0.footballMatch == nil
                && AstronomyMoment(eventTitle: $0.title) == nil
        }
        let fingerprint = makeEventTitleRewriteFingerprint(
            candidates: eligibleCandidates,
            maximumCharacters: maximumCharacters,
            includesDropdown: settings.useRewrittenEventTitlesInDropdown
        )
        guard eventTitleRewriteFingerprint != fingerprint else { return }

        eventTitleRewriteTask?.cancel()
        eventTitleRewriteFingerprint = fingerprint

        let eligibleKeys = Set(eligibleCandidates.map(\.notificationKey))
        rewrittenEventTitlesByItemKey = rewrittenEventTitlesByItemKey.filter {
            eligibleKeys.contains($0.key)
        }
        guard !eligibleCandidates.isEmpty else {
            eventTitleRewriteTask = nil
            return
        }

        eventTitleRewriteTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for item in eligibleCandidates {
                guard !Task.isCancelled else { return }
                let cacheKey = EventTitleRewriteCacheKey(
                    title: item.title,
                    maximumCharacters: maximumCharacters
                )

                let rewrittenTitle: String
                if let cachedTitle = eventTitleRewriteCache.value(forKey: cacheKey) {
                    rewrittenTitle = cachedTitle
                } else {
                    do {
                        let generatedTitle = try await eventTitleRewriter.rewriteTitle(
                            item.title,
                            maximumCharacters: maximumCharacters
                        )
                        try Task.checkCancellation()
                        rewrittenTitle = EventTitleRewriteResolver.resolvedTitle(
                            generatedTitle,
                            originalTitle: item.title,
                            maximumCharacters: maximumCharacters
                        )
                        eventTitleRewriteCache.insert(rewrittenTitle, forKey: cacheKey)
                    } catch is CancellationError {
                        return
                    } catch {
                        continue
                    }
                }

                rewrittenEventTitlesByItemKey[item.notificationKey] = rewrittenTitle
                updateMenuBarState(now: fixedSecondNow(), settings: snapshotSettings())
            }

            eventTitleRewriteTask = nil
        }
    }

    func eventTitle(for item: UpcomingItem, inDropdown: Bool) -> String {
        let settings = currentSettings
        guard settings.useEventTitleEllipsis,
              settings.rewriteEventTitlesWithAppleIntelligence,
              AppSettingsRules.allowsAppleIntelligenceTitleRewrite(
                maximumCharacters: settings.eventTitleMaxCharacters
              ),
              EventTitleRewriteResolver.shouldRequestRewrite(
                for: item.title,
                maximumCharacters: settings.eventTitleMaxCharacters
              ),
              (!inDropdown || settings.useRewrittenEventTitlesInDropdown) else {
            return item.title
        }
        return EventTitleRewriteResolver.resolvedTitle(
            rewrittenEventTitlesByItemKey[item.notificationKey],
            originalTitle: item.title,
            maximumCharacters: settings.eventTitleMaxCharacters
        )
    }

    func rewrittenEventTitle(for item: UpcomingItem, settings: AppSettings) -> String? {
        guard settings.useEventTitleEllipsis,
              settings.rewriteEventTitlesWithAppleIntelligence,
              AppSettingsRules.allowsAppleIntelligenceTitleRewrite(
                maximumCharacters: settings.eventTitleMaxCharacters
              ),
              EventTitleRewriteResolver.shouldRequestRewrite(
                for: item.title,
                maximumCharacters: settings.eventTitleMaxCharacters
              ) else {
            return nil
        }
        return rewrittenEventTitlesByItemKey[item.notificationKey]
    }

    private func cancelEventTitleRewrites(clearDisplayedTitles: Bool) {
        eventTitleRewriteTask?.cancel()
        eventTitleRewriteTask = nil
        eventTitleRewriteFingerprint = nil
        if clearDisplayedTitles, !rewrittenEventTitlesByItemKey.isEmpty {
            rewrittenEventTitlesByItemKey = [:]
        }
    }

    private func makeEventTitleRewriteFingerprint(
        candidates: [UpcomingItem],
        maximumCharacters: Int,
        includesDropdown: Bool
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(maximumCharacters)
        hasher.combine(includesDropdown)
        for item in candidates {
            hasher.combine(item.notificationKey)
            hasher.combine(item.title)
        }
        return hasher.finalize()
    }
}
