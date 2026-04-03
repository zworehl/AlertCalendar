import AppKit
import CoreLocation
import EventKit
import Foundation

extension CalendarMonitor {
    private static let footballMenuRefreshInterval: TimeInterval = 60
    private static let footballManagedSyncInterval: TimeInterval = 60
    private static let footballManagedCleanupInterval: TimeInterval = 6 * 60 * 60
    private static let footballTrackedLookbackDays = 30
    private static let footballTrackedLookaheadDays = 30
    private static let footballManagedCleanupSearchLookbackDays = 365
    private static let footballManagedCleanupSearchLookaheadDays = 365
    nonisolated private static let footballRegulationMatchDuration: TimeInterval = 110 * 60
    nonisolated private static let footballExtraTimeMatchDuration: TimeInterval = 140 * 60
    nonisolated private static let footballPenaltyMatchDuration: TimeInterval = 150 * 60
    nonisolated private static let footballLiveMinimumTailDuration: TimeInterval = 10 * 60
    nonisolated private static let footballEstimatedEndMarginDuration: TimeInterval = 5 * 60
    nonisolated private static let footballManagedEventMatchingTolerance: TimeInterval = 5 * 60
    nonisolated private static let footballStructuredLocationToleranceMeters: CLLocationDistance = 150

    private struct ManagedFootballEventSnapshot {
        let event: EKEvent
        let reference: ManagedFootballFixtureReference
        let record: ManagedFootballEventRecord
    }

    func refreshFootballDataIfNeeded(now: Date, force: Bool = false) async {
        await syncManagedFootballEventsIfNeeded(now: now, force: force)
    }

    func ensureFootballCompetitionSections() {
        let existingSectionsByID = Dictionary(uniqueKeysWithValues: footballMenuSections.map { ($0.id, $0) })
        footballMenuSections = FootballCompetitionPreset.menuPresets.map { preset in
            existingSectionsByID[preset.id] ?? .placeholder(for: preset)
        }
    }

    func loadFootballCompetitionSection(_ competition: FootballCompetitionPreset, force: Bool = true) async {
        ensureFootballCompetitionSections()
        guard let existingSection = footballMenuSections.first(where: { $0.id == competition.id }) else { return }
        guard !existingSection.isLoading else { return }
        guard force || !existingSection.hasLoaded else { return }

        let now = fixedSecondNow()
        let cachedMatches = cachedCompetitionMatches(for: competition, now: now)
        let hasCachedMatches = !cachedMatches.isEmpty

        updateFootballCompetitionSection(competition.id) { currentSection in
            FootballMenuCompetitionSection(
                competition: currentSection.competition,
                matches: hasCachedMatches ? cachedMatches : currentSection.matches,
                errorMessage: nil,
                isLoading: true,
                hasLoaded: currentSection.hasLoaded || hasCachedMatches
            )
        }

        do {
            let matchesByCompetition = try await footballClient.fetchMatchesByCompetition(for: [competition])
            let fetchedMatches = matchesByCompetition[competition.slug] ?? []
            let refreshedMatches = await footballClient.refreshStatusesIfNeeded(for: fetchedMatches)
            await cacheFootballMatches(refreshedMatches)
            let matches = Self.resolvedFootballSectionMatches(
                refreshedMatches,
                cachedMatchesByID: footballMatchesByID,
                now: now
            )

            updateFootballCompetitionSection(competition.id) { _ in
                FootballMenuCompetitionSection(
                    competition: competition,
                    matches: matches,
                    errorMessage: nil,
                    isLoading: false,
                    hasLoaded: true
                )
            }
        } catch {
            updateFootballCompetitionSection(competition.id) { currentSection in
                FootballMenuCompetitionSection(
                    competition: currentSection.competition,
                    matches: currentSection.matches,
                    errorMessage: currentSection.hasLoaded
                        ? "Could not refresh fixtures right now. Showing cached matches."
                        : "Could not load fixtures right now.",
                    isLoading: false,
                    hasLoaded: currentSection.hasLoaded
                )
            }
        }
    }

    func loadFootballLiveAndNextDaySection(force: Bool = true) async {
        guard !footballLiveAndNextDaySection.isLoading else { return }
        guard force || !footballLiveAndNextDaySection.hasLoaded else { return }

        let now = fixedSecondNow()
        let cachedMatches = Self.liveAndNextDayMatches(from: Array(footballMatchesByID.values), now: now)
        let hasCachedMatches = !cachedMatches.isEmpty

        footballLiveAndNextDaySection = FootballMatchesOverviewSection(
            title: footballLiveAndNextDaySection.title,
            matches: hasCachedMatches ? cachedMatches : footballLiveAndNextDaySection.matches,
            errorMessage: nil,
            isLoading: true,
            hasLoaded: footballLiveAndNextDaySection.hasLoaded || hasCachedMatches
        )

        let limitedPresets = FootballCompetitionPreset.menuPresets.map {
            FootballCompetitionPreset(
                slug: $0.slug,
                title: $0.title,
                lookbackDays: 1,
                lookaheadDays: 2,
                category: $0.category
            )
        }

        do {
            let fetchedMatches = try await footballClient.fetchMatches(for: limitedPresets)
            let refreshedMatches = await footballClient.refreshStatusesIfNeeded(for: fetchedMatches)
            await cacheFootballMatches(refreshedMatches)
            let filteredMatches = Self.liveAndNextDayMatches(
                from: Self.resolvedFootballSectionMatches(
                    refreshedMatches,
                    cachedMatchesByID: footballMatchesByID,
                    now: now
                ),
                now: now
            )

            footballLiveAndNextDaySection = FootballMatchesOverviewSection(
                title: footballLiveAndNextDaySection.title,
                matches: filteredMatches,
                errorMessage: nil,
                isLoading: false,
                hasLoaded: true
            )
        } catch {
            footballLiveAndNextDaySection = FootballMatchesOverviewSection(
                title: footballLiveAndNextDaySection.title,
                matches: hasCachedMatches ? cachedMatches : footballLiveAndNextDaySection.matches,
                errorMessage: footballLiveAndNextDaySection.hasLoaded || hasCachedMatches
                    ? "Could not refresh live or 48-hour fixtures right now. Showing cached matches."
                    : "Could not load live or 48-hour fixtures right now.",
                isLoading: false,
                hasLoaded: footballLiveAndNextDaySection.hasLoaded || hasCachedMatches
            )
        }
    }

    func syncManagedFootballEventsIfNeeded(now: Date, force: Bool = false) async {
        guard hasEventsAccess else {
            managedFootballMatchIDs = []
            managedFootballMatches = []
            return
        }

        migrateLegacyManagedFootballEventsIfNeeded(now: now)
        await recoverManagedFootballEventRecordsIfNeeded(now: now)

        let needsCleanup = force
            || lastFootballManagedCleanupDate == nil
            || now.timeIntervalSince(lastFootballManagedCleanupDate!) >= Self.footballManagedCleanupInterval
        if needsCleanup {
            _ = removeManagedFootballEventsOutsideSuggestionWindow(now: now)
            lastFootballManagedCleanupDate = now
        }

        let trackedEvents = trackedFootballSnapshotsByRefreshingState(now: now)
        applyManagedFootballAlertConfigurationIfNeeded(to: trackedEvents)

        guard !trackedEvents.isEmpty else {
            managedFootballMatches = []
            return
        }

        let needsNetworkRefresh = force
            || lastFootballManagedSyncDate == nil
            || now.timeIntervalSince(lastFootballManagedSyncDate!) >= Self.footballManagedSyncInterval
            || trackedEvents.contains { footballMatchesByID[$0.reference.matchID] == nil }

        guard needsNetworkRefresh else { return }

        let trackedPresets = deduplicatedFootballPresets(from: trackedEvents.map(\.reference.competitionSlug))
        do {
            let matches = try await footballClient.fetchMatches(for: trackedPresets)
            let refreshedMatches = await footballClient.refreshStatusesIfNeeded(for: matches)
            await cacheFootballMatches(refreshedMatches)
            updateManagedFootballMatches(using: trackedEvents, now: now)
            await applyFootballEventUpdates(trackedEvents, using: refreshedMatches)
            lastFootballManagedSyncDate = now
        } catch {
            return
        }
    }

    func applyManagedFootballAlertConfigurationIfNeeded(now: Date) {
        guard hasEventsAccess else { return }
        let trackedEvents = trackedFootballSnapshotsByRefreshingState(now: now)
        applyManagedFootballAlertConfigurationIfNeeded(to: trackedEvents)
    }

    func addFootballMatchToCalendar(_ match: FootballFixtureMatch) async {
        guard hasEventsAccess else {
            calendarAccessDescription = "Calendar access is required to add fixtures."
            return
        }

        guard let calendar = resolvedFootballTargetCalendar() else {
            calendarAccessDescription = "Choose a writable event calendar before adding fixtures."
            return
        }

        let reference = ManagedFootballFixtureReference(
            matchID: match.id,
            competitionSlug: match.competitionSlug
        )
        if trackedFootballEvents(now: Date()).contains(where: { $0.reference == reference }) {
            await cacheFootballMatches([match])
            managedFootballMatchIDs.insert(match.id)
            updateManagedFootballMatches(using: trackedFootballEvents(now: Date()), now: Date())
            refreshNow()
            return
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = FootballFixtureFormatter.calendarTitle(for: match)
        await applyFootballLocation(to: event, locationText: match.locationText)
        event.startDate = Self.footballEffectiveStartDate(for: match)
        event.endDate = approximateEndDate(for: match)
        applyFootballAlertConfiguration(to: event)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            let persistedEvent = persistCleanFootballAlertConfigurationIfNeeded(for: event.eventIdentifier) ?? event
            await cacheFootballMatches([match])
            ensureFootballTargetCalendarIsSelected(calendar.calendarIdentifier)
            upsertManagedFootballEventRecord(for: persistedEvent, reference: reference)
            managedFootballMatchIDs.insert(match.id)
            updateManagedFootballMatches(using: trackedFootballEvents(now: Date()), now: Date())
            refreshNow()
        } catch {
            calendarAccessDescription = "Could not save the selected fixture."
        }
    }

    func openFootballMatchInCalendar(_ match: FootballFixtureMatch) {
        let reference = ManagedFootballFixtureReference(
            matchID: match.id,
            competitionSlug: match.competitionSlug
        )

        guard let snapshot = trackedFootballEvents(now: Date()).first(where: { $0.reference == reference }) else {
            calendarAccessDescription = "Could not find the selected fixture in Calendar."
            _ = openCalendarApplication()
            return
        }

        Task { @MainActor in
            _ = openCalendarApplication()

            if revealCalendarEvent(snapshot.event) {
                return
            }

            try? await Task.sleep(nanoseconds: 350_000_000)
            if revealCalendarEvent(snapshot.event) {
                return
            }

            try? await Task.sleep(nanoseconds: 850_000_000)
            if revealCalendarEvent(snapshot.event) {
                return
            }

            calendarAccessDescription = "Could not reveal the event directly in Calendar."
            _ = openCalendarApplication()
        }
    }

    func removeFootballMatchFromCalendar(_ match: FootballFixtureMatch) {
        guard hasEventsAccess else {
            calendarAccessDescription = "Calendar access is required to remove fixtures."
            return
        }

        let reference = ManagedFootballFixtureReference(
            matchID: match.id,
            competitionSlug: match.competitionSlug
        )
        let trackedSnapshots = trackedFootballEvents(now: Date()).filter { $0.reference == reference }

        guard !trackedSnapshots.isEmpty else {
            removeManagedFootballEventRecord(for: reference)
            managedFootballMatchIDs.remove(match.id)
            updateManagedFootballMatches(using: trackedFootballEvents(now: Date()), now: Date())
            refreshNow()
            return
        }

        var removedAny = false
        for snapshot in trackedSnapshots {
            do {
                try eventStore.remove(snapshot.event, span: .thisEvent, commit: false)
                removedAny = true
            } catch {
                continue
            }
        }

        guard removedAny else {
            calendarAccessDescription = "Could not remove the selected fixture."
            return
        }

        do {
            try eventStore.commit()
            removeManagedFootballEventRecord(for: reference)
            managedFootballMatchIDs.remove(match.id)
            updateManagedFootballMatches(using: trackedFootballEvents(now: Date()), now: Date())
            refreshNow()
        } catch {
            calendarAccessDescription = "Could not remove the selected fixture."
        }
    }

    func writableFootballTargetCalendars() -> [AvailableCalendar] {
        footballTargetCalendars().map {
                AvailableCalendar(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    color: color(from: $0),
                    kind: .event,
                    accountTitle: normalizedAccountTitle(for: $0),
                    isSubscribed: $0.type == .subscription
                )
            }
    }

    func footballTargetCalendarID() -> String? {
        resolvedFootballTargetCalendar()?.calendarIdentifier
    }

    func isFootballMatchTracked(_ match: FootballFixtureMatch) -> Bool {
        managedFootballMatchIDs.contains(match.id)
    }

    func refreshManagedFootballTrackingSnapshot(now: Date) {
        guard hasEventsAccess else {
            managedFootballMatchIDs = []
            managedFootballMatches = []
            return
        }
        _ = trackedFootballSnapshotsByRefreshingState(now: now)
    }

    private func trackedFootballSnapshotsByRefreshingState(now: Date) -> [ManagedFootballEventSnapshot] {
        _ = removeDuplicateManagedFootballEvents(now: now)
        let trackedEvents = trackedFootballEvents(now: now)
        let trackedMatchIDs = Set(trackedEvents.map(\.reference.matchID))
        if trackedMatchIDs != managedFootballMatchIDs {
            managedFootballMatchIDs = trackedMatchIDs
        }
        updateManagedFootballMatches(using: trackedEvents, now: now)
        return trackedEvents
    }

    private func footballCalendarAlertOption() -> FootballCalendarAlertOption {
        FootballCalendarAlertOption(rawValue: defaults.string(forKey: DefaultsKeys.footballCalendarAlertOption) ?? "")
            ?? .none
    }

    private func footballCalendarAlertRelativeOffset() -> TimeInterval? {
        footballCalendarAlertOption().relativeOffset()
    }

    private func footballTravelTime(for event: EKEvent) -> TimeInterval {
        if let raw = (event as NSObject).value(forKey: "travelTime") as? NSNumber {
            return max(0, raw.doubleValue)
        }
        if let raw = (event as NSObject).value(forKey: "travelTime") as? Double {
            return max(0, raw)
        }
        return 0
    }

    private func resetFootballTravelTime(on event: EKEvent) {
        (event as NSObject).setValue(0, forKey: "travelTime")
    }

    private func footballAlertConfigurationNeedsUpdate(
        for event: EKEvent,
        desiredRelativeOffset: TimeInterval?
    ) -> Bool {
        let alarms = event.alarms ?? []

        guard let desiredRelativeOffset else {
            return !alarms.isEmpty
        }

        guard alarms.count == 1, let alarm = alarms.first else {
            return true
        }

        if alarm.absoluteDate != nil {
            return true
        }

        if abs(alarm.relativeOffset - desiredRelativeOffset) > 1 {
            return true
        }

        return footballTravelTime(for: event) > 0
    }

    private func applyFootballAlertConfiguration(to event: EKEvent) {
        let desiredRelativeOffset = footballCalendarAlertRelativeOffset()

        guard footballAlertConfigurationNeedsUpdate(for: event, desiredRelativeOffset: desiredRelativeOffset) else {
            return
        }

        resetFootballTravelTime(on: event)
        if let desiredRelativeOffset {
            event.alarms = [EKAlarm(relativeOffset: desiredRelativeOffset)]
        } else {
            event.alarms = nil
        }
    }

    @discardableResult
    private func persistCleanFootballAlertConfigurationIfNeeded(for eventIdentifier: String?) -> EKEvent? {
        guard let eventIdentifier else { return nil }

        let desiredRelativeOffset = footballCalendarAlertRelativeOffset()
        var latestEvent = eventStore.event(withIdentifier: eventIdentifier)

        for _ in 0 ..< 2 {
            guard let event = latestEvent else { return nil }
            guard footballAlertConfigurationNeedsUpdate(for: event, desiredRelativeOffset: desiredRelativeOffset) else {
                return event
            }

            resetFootballTravelTime(on: event)
            if let desiredRelativeOffset {
                event.alarms = [EKAlarm(relativeOffset: desiredRelativeOffset)]
            } else {
                event.alarms = nil
            }

            do {
                try eventStore.save(event, span: .thisEvent, commit: true)
            } catch {
                return event
            }

            latestEvent = eventStore.event(withIdentifier: eventIdentifier) ?? event
        }

        return latestEvent
    }

    private func refreshManagedFootballRecordsAfterPersistedAlertCleanup(
        _ recordsByReference: inout [ManagedFootballFixtureReference: ManagedFootballEventRecord],
        references: [ManagedFootballFixtureReference]
    ) {
        for reference in references {
            guard let existingRecord = recordsByReference[reference] else { continue }
            guard let cleanedEvent = persistCleanFootballAlertConfigurationIfNeeded(for: existingRecord.eventIdentifier) else {
                continue
            }

            recordsByReference[reference] = managedFootballEventRecord(
                for: cleanedEvent,
                reference: reference
            )
        }
    }

    private func applyManagedFootballAlertConfigurationIfNeeded(to trackedEvents: [ManagedFootballEventSnapshot]) {
        let desiredRelativeOffset = footballCalendarAlertRelativeOffset()
        var hasPendingChanges = false
        var refreshedRecordsByReference = Dictionary(uniqueKeysWithValues: managedFootballEventRecords.map { ($0.reference, $0) })
        var updatedReferences: [ManagedFootballFixtureReference] = []

        for snapshot in trackedEvents {
            guard footballAlertConfigurationNeedsUpdate(for: snapshot.event, desiredRelativeOffset: desiredRelativeOffset) else {
                continue
            }

            resetFootballTravelTime(on: snapshot.event)
            if let desiredRelativeOffset {
                snapshot.event.alarms = [EKAlarm(relativeOffset: desiredRelativeOffset)]
            } else {
                snapshot.event.alarms = nil
            }

            do {
                try eventStore.save(snapshot.event, span: .thisEvent, commit: false)
                refreshedRecordsByReference[snapshot.reference] = managedFootballEventRecord(
                    for: snapshot.event,
                    reference: snapshot.reference
                )
                updatedReferences.append(snapshot.reference)
                hasPendingChanges = true
            } catch {
                continue
            }
        }

        if hasPendingChanges {
            try? eventStore.commit()
            refreshManagedFootballRecordsAfterPersistedAlertCleanup(
                &refreshedRecordsByReference,
                references: updatedReferences
            )
            persistManagedFootballEventRecords(Array(refreshedRecordsByReference.values))
        }
    }

    func upcomingManagedFootballEventCount(now: Date) -> Int {
        trackedFootballEvents(now: now).reduce(into: Set<String>()) { matchIDs, snapshot in
            let startDate = snapshot.event.startDate ?? snapshot.record.startDate
            let endDate = snapshot.event.endDate ?? startDate
            if startDate > now || endDate > now {
                matchIDs.insert(snapshot.reference.matchID)
            }
        }
        .count
    }

    func footballMatchStatusText(_ match: FootballFixtureMatch) -> String {
        if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
            return "Starting soon"
        }

        switch match.statusState {
        case .inProgress:
            return match.statusText
        case .finished:
            return "FT"
        case .scheduled, .unknown:
            return Self.footballKickoffStatusText(for: match.startDate)
        }
    }

    func shouldRefreshFootballOnHeartbeat(now: Date) -> Bool {
        guard !managedFootballMatchIDs.isEmpty else {
            return false
        }

        let lastManagedRefresh = lastFootballManagedSyncDate?.timeIntervalSince1970 ?? 0
        if lastManagedRefresh <= 0 {
            return true
        }

        return now.timeIntervalSince1970 - lastManagedRefresh >= Self.footballManagedSyncInterval
    }

    private func trackedFootballEvents(now: Date) -> [ManagedFootballEventSnapshot] {
        resolveManagedFootballEventSnapshots().filter { snapshot in
            let startDate = snapshot.event.startDate ?? snapshot.record.startDate
            return Self.isManagedFootballEventWithinSuggestionWindow(startDate: startDate, now: now)
        }
    }

    private func resolveManagedFootballEventSnapshots() -> [ManagedFootballEventSnapshot] {
        let deduplicatedRecords = deduplicatedManagedFootballEventRecords(managedFootballEventRecords)
        var resolvedSnapshots: [ManagedFootballEventSnapshot] = []
        var refreshedRecords: [ManagedFootballEventRecord] = []

        for record in deduplicatedRecords {
            guard let event = resolveManagedFootballEvent(for: record) else {
                continue
            }

            let refreshedRecord = managedFootballEventRecord(for: event, reference: record.reference)
            refreshedRecords.append(refreshedRecord)
            resolvedSnapshots.append(
                ManagedFootballEventSnapshot(
                    event: event,
                    reference: refreshedRecord.reference,
                    record: refreshedRecord
                )
            )
        }

        persistManagedFootballEventRecords(refreshedRecords)
        return resolvedSnapshots
    }

    private func legacyManagedFootballEventSnapshots(
        now: Date,
        lookbackDays: Int,
        lookaheadDays: Int
    ) -> [ManagedFootballEventSnapshot] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: lookaheadDays, to: now) ?? now
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: eventStore.calendars(for: .event)
        )

        return eventStore.events(matching: predicate).compactMap { event in
            guard let reference = ManagedFootballFixtureReference.parse(from: event.url) else { return nil }
            return ManagedFootballEventSnapshot(
                event: event,
                reference: reference,
                record: managedFootballEventRecord(for: event, reference: reference)
            )
        }
    }

    @discardableResult
    private func removeManagedFootballEventsOutsideSuggestionWindow(now: Date) -> Int {
        var removedCount = 0
        var survivingRecords: [ManagedFootballEventRecord] = []

        for record in deduplicatedManagedFootballEventRecords(managedFootballEventRecords) {
            let resolvedEvent = resolveManagedFootballEvent(for: record)
            let effectiveStartDate = resolvedEvent?.startDate ?? record.startDate

            guard Self.isManagedFootballEventWithinSuggestionWindow(startDate: effectiveStartDate, now: now) else {
                if let resolvedEvent {
                    do {
                        try eventStore.remove(resolvedEvent, span: .thisEvent, commit: false)
                        removedCount += 1
                    } catch {
                        continue
                    }
                }
                continue
            }

            if let resolvedEvent {
                survivingRecords.append(managedFootballEventRecord(for: resolvedEvent, reference: record.reference))
            } else {
                survivingRecords.append(record)
            }
        }

        if removedCount > 0 {
            try? eventStore.commit()
        }

        persistManagedFootballEventRecords(survivingRecords)

        return removedCount
    }

    private func deduplicatedFootballPresets(from competitionSlugs: [String]) -> [FootballCompetitionPreset] {
        var seen = Set<String>()
        return competitionSlugs.compactMap { slug in
            guard seen.insert(slug).inserted else { return nil }
            if let preset = FootballCompetitionPreset.menuPresets.first(where: { $0.slug == slug }) {
                return preset
            }
            return FootballCompetitionPreset(
                slug: slug,
                title: slug.replacingOccurrences(of: ".", with: " ").capitalized,
                lookbackDays: 30,
                lookaheadDays: 30
            )
        }
    }

    @discardableResult
    func removeDuplicateManagedFootballEvents(now: Date = Date()) -> Int {
        let deduplicatedRecords = deduplicatedManagedFootballEventRecords(managedFootballEventRecords)
        let removedCount = max(0, managedFootballEventRecords.count - deduplicatedRecords.count)
        persistManagedFootballEventRecords(deduplicatedRecords)
        return removedCount
    }

    private func cacheFootballMatches(_ matches: [FootballFixtureMatch]) async {
        guard !matches.isEmpty else { return }
        let now = Date()
        for match in matches {
            if let previousMatch = footballMatchesByID[match.id],
               let goalHighlight = Self.goalHighlight(from: previousMatch, to: match, now: now) {
                activeFootballGoalHighlight = goalHighlight
            }
            footballMatchesByID[match.id] = match
        }

        let teams = matches
            .flatMap { [$0.homeTeam, $0.awayTeam] }
            .reduce(into: [String: FootballTeamSummary]()) { partialResult, team in
                partialResult[team.id] = team
            }

        for team in teams.values {
            guard footballLocalLogoPathsByTeamID[team.id] == nil else { continue }
            guard let localLogo = await footballImageStore.localFileURL(for: team.logoURL) else { continue }
            footballLocalLogoPathsByTeamID[team.id] = localLogo.path
        }

        for match in matches {
            guard footballLocalLogoPathsByCompetitionSlug[match.competitionSlug] == nil else { continue }
            guard let localLogo = await footballImageStore.localFileURL(for: match.competitionLogoURL) else { continue }
            footballLocalLogoPathsByCompetitionSlug[match.competitionSlug] = localLogo.path
        }
    }

    private func cachedCompetitionMatches(for competition: FootballCompetitionPreset, now: Date) -> [FootballFixtureMatch] {
        Array(footballMatchesByID.values)
            .filter { $0.competitionSlug == competition.slug }
            .filter { match in
                Self.isManagedFootballEventWithinSuggestionWindow(startDate: match.startDate, now: now)
            }
            .sorted { lhs, rhs in
                Self.footballFixtureSortPriority(for: lhs, now: now) < Self.footballFixtureSortPriority(for: rhs, now: now)
            }
    }

    private func applyFootballEventUpdates(_ trackedEvents: [ManagedFootballEventSnapshot], using matches: [FootballFixtureMatch]) async {
        let matchesByID = Dictionary(uniqueKeysWithValues: matches.map { ($0.id, $0) })
        var hasPendingChanges = false
        var refreshedRecordsByReference = Dictionary(uniqueKeysWithValues: managedFootballEventRecords.map { ($0.reference, $0) })
        var updatedReferences: [ManagedFootballFixtureReference] = []

        for snapshot in trackedEvents {
            guard let match = matchesByID[snapshot.reference.matchID] else { continue }
            let updatedTitle = FootballFixtureFormatter.calendarTitle(for: match)
            let updatedLocation = match.locationText
            let updatedStartDate = Self.footballEffectiveStartDate(for: match)
            let updatedEndDate = approximateEndDate(for: match)
            let needsStructuredLocationUpdate = await footballStructuredLocationNeedsUpdate(
                for: snapshot.event,
                locationText: updatedLocation
            )
            let needsAlertUpdate = footballAlertConfigurationNeedsUpdate(
                for: snapshot.event,
                desiredRelativeOffset: footballCalendarAlertRelativeOffset()
            )

            let needsUpdate = snapshot.event.title != updatedTitle
                || snapshot.event.location != updatedLocation
                || snapshot.event.startDate != updatedStartDate
                || snapshot.event.endDate != updatedEndDate
                || snapshot.event.url != nil
                || needsStructuredLocationUpdate
                || needsAlertUpdate

            guard needsUpdate else { continue }

            snapshot.event.title = updatedTitle
            await applyFootballLocation(to: snapshot.event, locationText: updatedLocation)
            snapshot.event.startDate = updatedStartDate
            snapshot.event.endDate = updatedEndDate
            snapshot.event.url = nil
            applyFootballAlertConfiguration(to: snapshot.event)

            do {
                try eventStore.save(snapshot.event, span: .thisEvent, commit: false)
                refreshedRecordsByReference[snapshot.reference] = managedFootballEventRecord(
                    for: snapshot.event,
                    reference: snapshot.reference
                )
                updatedReferences.append(snapshot.reference)
                hasPendingChanges = true
            } catch {
                continue
            }
        }

        if hasPendingChanges {
            try? eventStore.commit()
            refreshManagedFootballRecordsAfterPersistedAlertCleanup(
                &refreshedRecordsByReference,
                references: updatedReferences
            )
        }

        persistManagedFootballEventRecords(Array(refreshedRecordsByReference.values))
    }

    private func applyFootballLocation(to event: EKEvent, locationText: String?) async {
        let normalizedLocationText = normalizedLocation(for: locationText)
        event.location = normalizedLocationText
        event.structuredLocation = await footballStructuredLocation(for: normalizedLocationText)
    }

    private func footballStructuredLocationNeedsUpdate(for event: EKEvent, locationText: String?) async -> Bool {
        let normalizedLocationText = normalizedLocation(for: locationText)
        let currentStructuredTitle = normalizedLocation(for: event.structuredLocation?.title)

        switch normalizedLocationText {
        case nil:
            return event.structuredLocation != nil
        case let normalizedLocationText?:
            guard let structuredLocation = event.structuredLocation else {
                return true
            }

            guard currentStructuredTitle == normalizedLocationText else {
                return true
            }

            guard let currentGeoLocation = structuredLocation.geoLocation else {
                return true
            }

            guard let resolvedCoordinate = await LocationCoordinateResolver.shared.coordinate(for: normalizedLocationText) else {
                return false
            }

            let resolvedGeoLocation = CLLocation(
                latitude: resolvedCoordinate.latitude,
                longitude: resolvedCoordinate.longitude
            )

            return currentGeoLocation.distance(from: resolvedGeoLocation) > Self.footballStructuredLocationToleranceMeters
        }
    }

    private func footballStructuredLocation(for locationText: String?) async -> EKStructuredLocation? {
        guard let locationText else { return nil }

        let structuredLocation = EKStructuredLocation(title: locationText)
        if let coordinate = await LocationCoordinateResolver.shared.coordinate(for: locationText) {
            structuredLocation.geoLocation = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }

        return structuredLocation
    }

    private func approximateEndDate(for match: FootballFixtureMatch) -> Date {
        Self.approximateFootballMatchEndDate(for: match, now: Date())
    }

    nonisolated static func approximateFootballMatchEndDate(
        for match: FootballFixtureMatch,
        now: Date = Date()
    ) -> Date {
        let approximatedDuration = approximateFootballMatchDuration(for: match, now: now)
        let effectiveStartDate = footballEffectiveStartDate(for: match)
        let bufferedEstimatedEnd = effectiveStartDate.addingTimeInterval(
            approximatedDuration + footballEstimatedEndMarginDuration
        )

        switch match.statusState {
        case .finished:
            return bufferedEstimatedEnd
        case .inProgress:
            let minimumLiveEnd = now.addingTimeInterval(footballLiveMinimumTailDuration)
            return max(bufferedEstimatedEnd, minimumLiveEnd)
        case .scheduled:
            return bufferedEstimatedEnd
        case .unknown:
            if effectiveStartDate <= now {
                let minimumLiveEnd = now.addingTimeInterval(footballLiveMinimumTailDuration)
                return max(bufferedEstimatedEnd, minimumLiveEnd)
            }
            return bufferedEstimatedEnd
        }
    }

    nonisolated static func approximateFootballMatchDuration(
        for match: FootballFixtureMatch,
        now: Date = Date()
    ) -> TimeInterval {
        let normalizedStatus = footballNormalizedStatusText(match.statusText)

        if let interruptionBadge = footballInterruptedStatusBadgeText(from: normalizedStatus) {
            return footballInterruptedMatchDuration(for: match, badgeText: interruptionBadge)
        }

        if footballStatusIndicatesPenaltyShootout(for: match, now: now) {
            return footballPenaltyMatchDuration
        }

        if footballStatusIndicatesExtraTime(for: match, now: now) {
            return footballExtraTimeMatchDuration
        }

        guard footballCanReachExtraTime(match) else {
            return footballRegulationMatchDuration
        }

        switch match.statusState {
        case .finished:
            return footballRegulationMatchDuration
        case .scheduled:
            return footballExtraTimeMatchDuration
        case .inProgress, .unknown:
            return footballExtraTimeStillLooksLikely(for: match, now: now)
                ? footballExtraTimeMatchDuration
                : footballRegulationMatchDuration
        }
    }

    nonisolated private static func footballFixtureSortPriority(
        for match: FootballFixtureMatch,
        now: Date
    ) -> (Int, TimeInterval, String) {
        if match.statusState == .inProgress {
            return (0, match.startDate.timeIntervalSince1970, match.id)
        }

        if match.startDate >= now {
            return (1, match.startDate.timeIntervalSince1970, match.id)
        }

        return (2, -match.startDate.timeIntervalSince1970, match.id)
    }

    nonisolated static func resolvedFootballSectionMatches(
        _ matches: [FootballFixtureMatch],
        cachedMatchesByID: [String: FootballFixtureMatch],
        now: Date
    ) -> [FootballFixtureMatch] {
        matches
            .map { cachedMatchesByID[$0.id] ?? $0 }
            .sorted { lhs, rhs in
                footballFixtureSortPriority(for: lhs, now: now) < footballFixtureSortPriority(for: rhs, now: now)
            }
    }

    private func updateFootballCompetitionSection(
        _ competitionID: String,
        transform: (FootballMenuCompetitionSection) -> FootballMenuCompetitionSection
    ) {
        guard let index = footballMenuSections.firstIndex(where: { $0.id == competitionID }) else { return }
        footballMenuSections[index] = transform(footballMenuSections[index])
    }

    private func updateManagedFootballMatches(using trackedEvents: [ManagedFootballEventSnapshot], now: Date) {
        let snapshotsByMatchID = trackedEvents.reduce(into: [String: ManagedFootballEventSnapshot]()) { partialResult, snapshot in
            guard partialResult[snapshot.reference.matchID] == nil else { return }
            partialResult[snapshot.reference.matchID] = snapshot
        }

        managedFootballMatches = snapshotsByMatchID.values
            .compactMap { snapshot in
                footballMatchesByID[snapshot.reference.matchID]
            }
            .sorted { lhs, rhs in
                Self.footballFixtureSortPriority(for: lhs, now: now) < Self.footballFixtureSortPriority(for: rhs, now: now)
            }
    }

    nonisolated static func liveAndNextDayMatches(
        from matches: [FootballFixtureMatch],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [FootballFixtureMatch] {
        let upperBound = calendar.date(byAdding: .day, value: 2, to: now) ?? now.addingTimeInterval(48 * 60 * 60)

        let filteredMatches = matches
            .filter { match in
                if match.statusState == .inProgress {
                    return true
                }
                if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
                    return true
                }
                return match.startDate >= now && match.startDate <= upperBound
            }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                return lhs.id < rhs.id
            }

        return deduplicatedFootballMatches(filteredMatches)
    }

    nonisolated static func upcomingManagedFootballMatches(
        from matches: [FootballFixtureMatch],
        now: Date
    ) -> [FootballFixtureMatch] {
        let filteredMatches = matches
            .filter { match in
                if match.statusState == .inProgress {
                    return true
                }
                if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
                    return true
                }
                return match.startDate > now
            }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.statusState == .inProgress ? 0 : 1
                let rhsPriority = rhs.statusState == .inProgress ? 0 : 1
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                return lhs.id < rhs.id
            }

        return deduplicatedFootballMatches(filteredMatches)
    }

    nonisolated private static func deduplicatedFootballMatches(_ matches: [FootballFixtureMatch]) -> [FootballFixtureMatch] {
        var seen = Set<String>()
        return matches.filter { seen.insert($0.id).inserted }
    }

    private func migrateLegacyManagedFootballEventsIfNeeded(now: Date) {
        let legacySnapshots = legacyManagedFootballEventSnapshots(
            now: now,
            lookbackDays: Self.footballManagedCleanupSearchLookbackDays,
            lookaheadDays: Self.footballManagedCleanupSearchLookaheadDays
        )
        guard !legacySnapshots.isEmpty else { return }

        let preferredCalendarID = resolvedFootballTargetCalendar()?.calendarIdentifier
        let groupedSnapshots = Dictionary(grouping: legacySnapshots, by: \.reference)
        var recordsByReference = Dictionary(uniqueKeysWithValues: managedFootballEventRecords.map { ($0.reference, $0) })
        var needsCommit = false

        for (reference, snapshots) in groupedSnapshots {
            let sortedSnapshots = sortManagedFootballSnapshots(snapshots, preferredCalendarID: preferredCalendarID)
            guard let keeper = sortedSnapshots.first else { continue }

            if keeper.event.url != nil {
                keeper.event.url = nil
                do {
                    try eventStore.save(keeper.event, span: .thisEvent, commit: false)
                    needsCommit = true
                } catch {
                    continue
                }
            }

            recordsByReference[reference] = managedFootballEventRecord(for: keeper.event, reference: reference)

            for duplicate in sortedSnapshots.dropFirst() {
                do {
                    try eventStore.remove(duplicate.event, span: .thisEvent, commit: false)
                    needsCommit = true
                } catch {
                    continue
                }
            }
        }

        if needsCommit {
            try? eventStore.commit()
        }

        persistManagedFootballEventRecords(Array(recordsByReference.values))
    }

    private func sortManagedFootballSnapshots(
        _ snapshots: [ManagedFootballEventSnapshot],
        preferredCalendarID: String?
    ) -> [ManagedFootballEventSnapshot] {
        snapshots.sorted { lhs, rhs in
            let lhsPreferred = lhs.event.calendar.calendarIdentifier == preferredCalendarID
            let rhsPreferred = rhs.event.calendar.calendarIdentifier == preferredCalendarID
            if lhsPreferred != rhsPreferred {
                return lhsPreferred && !rhsPreferred
            }

            let lhsActive = lhs.event.endDate ?? lhs.event.startDate ?? .distantPast
            let rhsActive = rhs.event.endDate ?? rhs.event.startDate ?? .distantPast
            if lhsActive != rhsActive {
                return lhsActive > rhsActive
            }

            let lhsIdentifier = lhs.event.eventIdentifier ?? ""
            let rhsIdentifier = rhs.event.eventIdentifier ?? ""
            return lhsIdentifier < rhsIdentifier
        }
    }

    func managedFootballReference(for event: EKEvent) -> ManagedFootballFixtureReference? {
        if let legacyReference = ManagedFootballFixtureReference.parse(from: event.url) {
            return legacyReference
        }

        return managedFootballRecord(for: event)?.reference
    }

    func footballMatch(for event: EKEvent) -> FootballFixtureMatch? {
        if let reference = managedFootballReference(for: event),
           let match = footballMatchForManagedReference(reference) {
            return match
        }

        if let cachedMatch = matchedFootballFixture(
            for: event,
            in: Array(footballMatchesByID.values)
        ) {
            return cachedMatch
        }

        return matchedFootballFixture(for: event, in: managedFootballMatches)
    }

    private func managedFootballRecord(for event: EKEvent) -> ManagedFootballEventRecord? {
        let eventIdentifier = event.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventUID = normalizedEventUID(for: event)
        if let directRecord = managedFootballEventRecords.first(where: { record in
            if let eventUID, record.eventUID == eventUID {
                return true
            }

            if let eventIdentifier, record.eventIdentifier == eventIdentifier {
                return true
            }

            return false
        }) {
            return directRecord
        }

        guard let eventStartDate = event.startDate else { return nil }
        let nearbyRecords = managedFootballEventRecords.filter { record in
            record.calendarIdentifier == event.calendar.calendarIdentifier
                && abs(record.startDate.timeIntervalSince(eventStartDate)) <= Self.footballManagedEventMatchingTolerance
        }

        if nearbyRecords.count == 1 {
            return nearbyRecords[0]
        }

        let eventTitle = normalizedTitle(event.title)
        let titleMatchedRecords = nearbyRecords.filter { record in
            guard let match = footballMatchForManagedReference(record.reference) else { return false }
            return normalizedTitle(FootballFixtureFormatter.calendarTitle(for: match)) == eventTitle
        }

        if titleMatchedRecords.count == 1 {
            return titleMatchedRecords[0]
        }

        return nil
    }

    private func resolveManagedFootballEvent(for record: ManagedFootballEventRecord) -> EKEvent? {
        if let eventIdentifier = record.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eventIdentifier.isEmpty,
           let event = eventStore.calendarItem(withIdentifier: eventIdentifier) as? EKEvent {
            return event
        }

        let calendar = Calendar.current
        let searchStart = calendar.date(byAdding: .day, value: -3, to: record.startDate) ?? record.startDate.addingTimeInterval(-3 * 86_400)
        let searchEnd = calendar.date(byAdding: .day, value: 3, to: record.startDate) ?? record.startDate.addingTimeInterval(3 * 86_400)
        let targetCalendars = eventStore.calendars(for: .event).filter { $0.calendarIdentifier == record.calendarIdentifier }
        let predicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: targetCalendars.isEmpty ? nil : targetCalendars
        )
        let candidates = eventStore.events(matching: predicate)

        if let eventUID = record.eventUID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eventUID.isEmpty,
           let matchedByUID = candidates.first(where: { normalizedEventUID(for: $0) == eventUID }) {
            return matchedByUID
        }

        if let eventIdentifier = record.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eventIdentifier.isEmpty,
           let matchedByIdentifier = candidates.first(where: { $0.eventIdentifier == eventIdentifier }) {
            return matchedByIdentifier
        }

        let kickoffMatchedCandidates = candidates.filter { candidate in
            guard let candidateStartDate = candidate.startDate else { return false }
            return abs(candidateStartDate.timeIntervalSince(record.startDate)) <= Self.footballManagedEventMatchingTolerance
        }

        if kickoffMatchedCandidates.count == 1 {
            return kickoffMatchedCandidates[0]
        }

        if let match = footballMatchForManagedReference(record.reference) {
            let expectedTitle = normalizedTitle(FootballFixtureFormatter.calendarTitle(for: match))
            let titleMatchedCandidates = kickoffMatchedCandidates.filter { candidate in
                normalizedTitle(candidate.title) == expectedTitle
            }
            if titleMatchedCandidates.count == 1 {
                return titleMatchedCandidates[0]
            }
        }

        return nil
    }

    private func managedFootballEventRecord(
        for event: EKEvent,
        reference: ManagedFootballFixtureReference
    ) -> ManagedFootballEventRecord {
        ManagedFootballEventRecord(
            matchID: reference.matchID,
            competitionSlug: reference.competitionSlug,
            calendarIdentifier: event.calendar.calendarIdentifier,
            eventIdentifier: event.eventIdentifier,
            eventUID: normalizedEventUID(for: event),
            startDate: event.startDate ?? Date()
        )
    }

    private func upsertManagedFootballEventRecord(for event: EKEvent, reference: ManagedFootballFixtureReference) {
        var recordsByReference = Dictionary(uniqueKeysWithValues: managedFootballEventRecords.map { ($0.reference, $0) })
        recordsByReference[reference] = managedFootballEventRecord(for: event, reference: reference)
        persistManagedFootballEventRecords(Array(recordsByReference.values))
    }

    private func removeManagedFootballEventRecord(for reference: ManagedFootballFixtureReference) {
        persistManagedFootballEventRecords(
            managedFootballEventRecords.filter { $0.reference != reference }
        )
    }

    private func persistManagedFootballEventRecords(_ records: [ManagedFootballEventRecord]) {
        let normalizedRecords = deduplicatedManagedFootballEventRecords(records)
        guard normalizedRecords != managedFootballEventRecords else { return }

        managedFootballEventRecords = normalizedRecords
        if normalizedRecords.isEmpty {
            defaults.removeObject(forKey: DefaultsKeys.managedFootballEventRecords)
            return
        }

        if let data = try? JSONEncoder().encode(normalizedRecords) {
            defaults.set(data, forKey: DefaultsKeys.managedFootballEventRecords)
        }
    }

    private func deduplicatedManagedFootballEventRecords(_ records: [ManagedFootballEventRecord]) -> [ManagedFootballEventRecord] {
        var deduplicatedByReference: [ManagedFootballFixtureReference: ManagedFootballEventRecord] = [:]

        for record in records {
            let reference = record.reference
            if let existingRecord = deduplicatedByReference[reference] {
                let existingHasUID = !(existingRecord.eventUID ?? "").isEmpty
                let candidateHasUID = !(record.eventUID ?? "").isEmpty
                if existingHasUID == candidateHasUID {
                    if record.startDate >= existingRecord.startDate {
                        deduplicatedByReference[reference] = record
                    }
                } else if candidateHasUID {
                    deduplicatedByReference[reference] = record
                }
            } else {
                deduplicatedByReference[reference] = record
            }
        }

        return deduplicatedByReference.values.sorted { lhs, rhs in
            if lhs.competitionSlug != rhs.competitionSlug {
                return lhs.competitionSlug < rhs.competitionSlug
            }
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            return lhs.matchID < rhs.matchID
        }
    }

    nonisolated static func isManagedFootballEventWithinSuggestionWindow(
        startDate: Date,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        let trackedLookbackDays = 30
        let trackedLookaheadDays = 30
        let lowerBound = calendar.date(byAdding: .day, value: -trackedLookbackDays, to: now) ?? now
        let upperBound = calendar.date(byAdding: .day, value: trackedLookaheadDays, to: now) ?? now
        return startDate >= lowerBound && startDate <= upperBound
    }

    private func revealCalendarEvent(_ event: EKEvent) -> Bool {
        guard let eventUID = normalizedEventUID(for: event) else { return false }

        let script = Self.calendarRevealScript(eventUID: eventUID)

        return Self.runAppleScript(script)
    }

    private func normalizedEventUID(for event: EKEvent) -> String? {
        let externalID = event.calendarItemExternalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let externalID, !externalID.isEmpty {
            return externalID
        }

        let fallbackID = event.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackID, !fallbackID.isEmpty {
            return fallbackID
        }

        return nil
    }

    private func openCalendarApplication() -> Bool {
        let calendarAppURL = URL(fileURLWithPath: "/System/Applications/Calendar.app", isDirectory: true)
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: calendarAppURL, configuration: configuration) { _, error in
            if error != nil {
                NSWorkspace.shared.open(calendarAppURL)
            }
        }
        return true
    }

    nonisolated static func calendarRevealScript(eventUID: String) -> String {
        """
        tell application "Calendar"
            activate
            repeat with targetCalendar in every calendar
                try
                    set targetEvent to first event of targetCalendar whose uid is \(appleScriptStringLiteral(eventUID))
                    show targetEvent
                    return
                end try
            end repeat
            error "Could not find the requested event."
        end tell
        """
    }

    nonisolated private static func runAppleScript(_ source: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    nonisolated static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func footballTargetCalendars() -> [EKCalendar] {
        let allEventCalendars = eventStore.calendars(for: .event)
            .filter { $0.type != .subscription && $0.type != .birthday }

        let writableCalendars = allEventCalendars
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        if !writableCalendars.isEmpty {
            return writableCalendars
        }

        if let defaultCalendar = eventStore.defaultCalendarForNewEvents,
           defaultCalendar.type != .subscription,
           defaultCalendar.type != .birthday {
            let candidateCalendars = ([defaultCalendar] + allEventCalendars).reduce(into: [EKCalendar]()) { partialResult, calendar in
                guard partialResult.contains(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) == false else { return }
                partialResult.append(calendar)
            }
            return candidateCalendars.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }

        return allEventCalendars.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func resolvedFootballTargetCalendar() -> EKCalendar? {
        let writableCalendars = footballTargetCalendars()

        guard !writableCalendars.isEmpty else {
            defaults.removeObject(forKey: DefaultsKeys.footballTargetCalendarID)
            return nil
        }

        if let storedID = defaults.string(forKey: DefaultsKeys.footballTargetCalendarID),
           let stored = writableCalendars.first(where: { $0.calendarIdentifier == storedID }) {
            return stored
        }

        let selectedIDs = selectedCalendarIDs(for: .event)
        if let selected = writableCalendars.first(where: { selectedIDs.contains($0.calendarIdentifier) }) {
            defaults.set(selected.calendarIdentifier, forKey: DefaultsKeys.footballTargetCalendarID)
            return selected
        }

        if let defaultCalendar = eventStore.defaultCalendarForNewEvents,
           let resolvedDefaultCalendar = writableCalendars.first(where: { $0.calendarIdentifier == defaultCalendar.calendarIdentifier }) {
            defaults.set(resolvedDefaultCalendar.calendarIdentifier, forKey: DefaultsKeys.footballTargetCalendarID)
            return resolvedDefaultCalendar
        }

        if let defaultCalendar = eventStore.defaultCalendarForNewEvents,
           defaultCalendar.type != .subscription,
           defaultCalendar.type != .birthday {
            defaults.set(defaultCalendar.calendarIdentifier, forKey: DefaultsKeys.footballTargetCalendarID)
            return defaultCalendar
        }

        let fallback = writableCalendars[0]
        defaults.set(fallback.calendarIdentifier, forKey: DefaultsKeys.footballTargetCalendarID)
        return fallback
    }

    private func ensureFootballTargetCalendarIsSelected(_ calendarIdentifier: String) {
        var selectedIDs = selectedCalendarIDs(for: .event)
        guard !selectedIDs.contains(calendarIdentifier) else { return }
        selectedIDs.insert(calendarIdentifier)
        defaults.set(Array(selectedIDs), forKey: DefaultsKeys.selectedEventCalendarIDs)
    }

    func footballMatchForManagedReference(_ reference: ManagedFootballFixtureReference) -> FootballFixtureMatch? {
        footballMatchesByID[reference.matchID]
    }

    private func recoverManagedFootballEventRecordsIfNeeded(now: Date) async {
        let orphanEvents = unresolvedManagedFootballCandidateEvents(now: now)
        guard !orphanEvents.isEmpty else { return }

        var candidateMatches = Array(footballMatchesByID.values)
        let unresolvedEvents = orphanEvents.filter { matchedFootballFixture(for: $0, in: candidateMatches) == nil }

        if !unresolvedEvents.isEmpty {
            do {
                let fetchedMatches = try await footballClient.fetchMatches(for: FootballCompetitionPreset.menuPresets)
                let refreshedMatches = await footballClient.refreshStatusesIfNeeded(for: fetchedMatches)
                await cacheFootballMatches(refreshedMatches)
                candidateMatches = Array(footballMatchesByID.values)
            } catch {
                return
            }
        }

        var recordsByReference = Dictionary(uniqueKeysWithValues: managedFootballEventRecords.map { ($0.reference, $0) })
        var didRecoverRecord = false

        for event in orphanEvents {
            guard let matchedFixture = matchedFootballFixture(for: event, in: candidateMatches) else { continue }
            let reference = ManagedFootballFixtureReference(
                matchID: matchedFixture.id,
                competitionSlug: matchedFixture.competitionSlug
            )

            guard recordsByReference[reference] == nil else { continue }
            recordsByReference[reference] = managedFootballEventRecord(for: event, reference: reference)
            didRecoverRecord = true
        }

        guard didRecoverRecord else { return }
        persistManagedFootballEventRecords(Array(recordsByReference.values))
    }

    private func unresolvedManagedFootballCandidateEvents(now: Date) -> [EKEvent] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -Self.footballTrackedLookbackDays, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: Self.footballTrackedLookaheadDays, to: now) ?? now
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: eventStore.calendars(for: .event)
        )

        return eventStore.events(matching: predicate).filter { event in
            guard managedFootballReference(for: event) == nil else { return false }
            guard let eventStartDate = event.startDate else { return false }
            guard Self.isManagedFootballEventWithinSuggestionWindow(startDate: eventStartDate, now: now) else { return false }
            return FootballFixtureFormatter.looksLikeFootballCalendarTitle(normalizedTitle(event.title))
        }
    }

    private func matchedFootballFixture(
        for event: EKEvent,
        in matches: [FootballFixtureMatch]
    ) -> FootballFixtureMatch? {
        guard let eventStartDate = event.startDate else { return nil }

        let eventTitle = normalizedTitle(event.title)
        let eventIdentityKey = FootballFixtureFormatter.calendarIdentityKey(fromCalendarTitle: eventTitle)
        let nearbyMatches = matches.filter { match in
            abs(Self.footballEffectiveStartDate(for: match).timeIntervalSince(eventStartDate)) <= Self.footballManagedEventMatchingTolerance
        }

        let exactTitleMatches = nearbyMatches.filter { match in
            normalizedTitle(FootballFixtureFormatter.calendarTitle(for: match)) == eventTitle
        }
        if exactTitleMatches.count == 1 {
            return exactTitleMatches[0]
        }

        if let eventIdentityKey {
            let identityMatches = nearbyMatches.filter { match in
                FootballFixtureFormatter.calendarIdentityKey(for: match) == eventIdentityKey
            }
            if identityMatches.count == 1 {
                return identityMatches[0]
            }
        }

        return nil
    }

    func footballMenuBarDisplay(for match: FootballFixtureMatch) -> FootballMenuBarDisplay {
        let competitionLogoURL = footballLocalLogoPathsByCompetitionSlug[match.competitionSlug].map(URL.init(fileURLWithPath:))
        let homeLogoURL = footballLocalLogoPathsByTeamID[match.homeTeam.id].map(URL.init(fileURLWithPath:))
        let awayLogoURL = footballLocalLogoPathsByTeamID[match.awayTeam.id].map(URL.init(fileURLWithPath:))
        return FootballFixtureFormatter.menuBarDisplay(
            for: match,
            competitionLocalLogoURL: competitionLogoURL,
            homeLocalLogoURL: homeLogoURL,
            awayLocalLogoURL: awayLogoURL
        )
    }

    nonisolated static func goalHighlight(
        from previousMatch: FootballFixtureMatch,
        to currentMatch: FootballFixtureMatch,
        now _: Date
    ) -> FootballGoalHighlight? {
        guard currentMatch.statusReliability == .reported else { return nil }
        guard currentMatch.statusState == .inProgress || currentMatch.statusState == .finished else { return nil }

        let previousHomeScore = footballGoalValue(previousMatch.homeScore)
        let previousAwayScore = footballGoalValue(previousMatch.awayScore)
        let currentHomeScore = footballGoalValue(currentMatch.homeScore)
        let currentAwayScore = footballGoalValue(currentMatch.awayScore)

        let homeDelta = currentHomeScore - previousHomeScore
        let awayDelta = currentAwayScore - previousAwayScore

        let scoringSide: FootballScoreSide
        if homeDelta > 0 && awayDelta == 0 {
            scoringSide = .home
        } else if awayDelta > 0 && homeDelta == 0 {
            scoringSide = .away
        } else {
            return nil
        }
        return FootballGoalHighlight(
            matchID: currentMatch.id,
            scoringSide: scoringSide
        )
    }

    nonisolated static func footballKickoffStatusText(
        for startDate: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var resolvedCalendar = calendar
        resolvedCalendar.timeZone = timeZone

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.setLocalizedDateFormatFromTemplate("h:mm a")

        let todayStart = resolvedCalendar.startOfDay(for: now)
        let tomorrowStart = resolvedCalendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let dayAfterTomorrowStart = resolvedCalendar.date(byAdding: .day, value: 1, to: tomorrowStart) ?? tomorrowStart

        if startDate >= todayStart, startDate < tomorrowStart {
            return "Today \(timeFormatter.string(from: startDate))"
        }

        if startDate >= tomorrowStart, startDate < dayAfterTomorrowStart {
            return "Tomorrow \(timeFormatter.string(from: startDate))"
        }

        let dayDistance = abs(resolvedCalendar.dateComponents([.day], from: now, to: startDate).day ?? 0)
        let template = dayDistance < 7 ? "EEE h:mm a" : "MMM d h:mm a"

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: startDate)
    }

    nonisolated static func footballStartedStatusText(
        for startDate: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var resolvedCalendar = calendar
        resolvedCalendar.timeZone = timeZone

        let todayStart = resolvedCalendar.startOfDay(for: now)
        let startOfMatchDay = resolvedCalendar.startOfDay(for: startDate)

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone

        if startOfMatchDay == todayStart {
            formatter.setLocalizedDateFormatFromTemplate("h:mm a")
            return "Started \(formatter.string(from: startDate))"
        }

        let dayDistance = abs(resolvedCalendar.dateComponents([.day], from: startDate, to: now).day ?? 0)
        let template = dayDistance < 7 ? "EEE h:mm a" : "MMM d h:mm a"
        formatter.setLocalizedDateFormatFromTemplate(template)
        return "Started \(formatter.string(from: startDate))"
    }

    nonisolated static func footballStatusBadgeText(
        for match: FootballFixtureMatch,
        now: Date = Date()
    ) -> String? {
        if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
            return "Soon"
        }

        let trimmed = match.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = footballNormalizedStatusText(trimmed)

        if let interruptionBadge = footballInterruptedStatusBadgeText(from: normalized) {
            return interruptionBadge
        }

        if match.statusState == .finished {
            if normalized.contains("AET") {
                return "AET"
            }
            if normalized.contains("PEN") || normalized == "PK" || normalized.contains("PENALTY") {
                return "PEN"
            }
            return "FT"
        }

        if footballLooksLikeMinuteStatus(trimmed) {
            if let reportedMinute = footballParsedMinute(from: trimmed),
               let inferredMinute = footballInferredMinuteFromKickoff(for: match, now: now),
               shouldPreferInferredLiveMinute(
                   reportedMinute: reportedMinute,
                   inferredMinute: inferredMinute,
                   match: match
               ) {
                return "\(inferredMinute)'"
            }
            return trimmed
        }

        if normalized == "HT" || normalized.contains("HALF") {
            return "HT"
        }

        if normalized.contains("AET") {
            return "AET"
        }

        if normalized.contains("PEN") || normalized == "PK" || normalized.contains("PENALTY") {
            return "PEN"
        }

        if normalized == "ET" || normalized.contains("EXTRA TIME") {
            return "ET"
        }

        if footballStatusIndicatesPenaltyShootout(for: match, now: now) {
            return "PEN"
        }

        if footballStatusIndicatesExtraTime(for: match, now: now) {
            return "ET"
        }

        if let inferredMinute = footballLiveMinute(for: match, now: now),
           inferredMinute > 0,
           match.statusState == .inProgress,
           match.statusReliability == .reported {
            return "\(inferredMinute)'"
        }

        return nil
    }

    nonisolated static func footballStatusTintColor(for text: String) -> NSColor {
        let normalized = text.uppercased()
        if normalized == "ABN" {
            return .systemRed
        }
        if normalized == "SUSP." || normalized == "POSTP." {
            return .systemOrange
        }
        if normalized == "DELAY" {
            return .systemYellow
        }
        if normalized == "FT" {
            return .systemGray
        }
        if normalized.contains("AET") {
            return .systemPurple
        }
        if normalized.contains("PEN") || normalized == "PK" {
            return .systemRed
        }
        if normalized == "HT" {
            return .systemOrange
        }
        if normalized == "ET" {
            return .systemIndigo
        }
        if normalized == "SOON" {
            return .systemBlue
        }
        return .systemGreen
    }

    nonisolated static func footballStatusWarningText(for match: FootballFixtureMatch) -> String? {
        switch match.statusReliability {
        case .reported, .awaitingLiveData:
            return nil
        case .delayedLiveData:
            return "Kickoff time has passed, but ESPN still has not confirmed live match data for this fixture."
        }
    }

    nonisolated static func footballStatusWarningSummary(for match: FootballFixtureMatch) -> String? {
        switch match.statusReliability {
        case .reported, .awaitingLiveData:
            return nil
        case .delayedLiveData:
            return "Live data fetch delayed"
        }
    }

    nonisolated private static func footballExtraTimeStillLooksLikely(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Bool {
        if footballScoresAreLevel(match) {
            return true
        }

        let goalMargin = abs(footballGoalValue(match.homeScore) - footballGoalValue(match.awayScore))
        let minute = footballLiveMinute(for: match, now: now) ?? 0

        if goalMargin >= 2 {
            return minute < 35
        }

        return minute < 72
    }

    nonisolated private static func footballStatusIndicatesExtraTime(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Bool {
        let normalizedStatus = footballNormalizedStatusText(match.statusText)
        let minute = footballLiveMinute(for: match, now: now)

        if normalizedStatus.contains("AET") {
            return true
        }

        if normalizedStatus == "ET" || normalizedStatus.contains("EXTRA TIME") {
            return true
        }

        guard footballCanReachExtraTime(match) else { return false }
        guard footballScoresAreLevel(match) else { return false }

        if let minute, minute >= 90 {
            return true
        }

        return false
    }

    nonisolated private static func footballStatusIndicatesPenaltyShootout(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Bool {
        let normalizedStatus = footballNormalizedStatusText(match.statusText)
        let normalizedNote = footballNormalizedStatusText(match.competitionNote ?? "")
        let minute = footballLiveMinute(for: match, now: now)

        if normalizedStatus.contains("PEN") || normalizedStatus == "PK" || normalizedStatus.contains("PENALTY") {
            return true
        }

        if normalizedNote.contains("PENALTY") || normalizedNote.contains("PENALTIES") {
            return true
        }

        guard footballCanReachExtraTime(match) else { return false }
        guard footballScoresAreLevel(match) else { return false }

        if let minute, minute >= 120 {
            return true
        }

        return false
    }

    nonisolated private static func footballCanReachExtraTime(_ match: FootballFixtureMatch) -> Bool {
        switch match.competitionSlug {
        case "eng.1", "esp.1", "bra.1", "ita.1", "ger.1", "fra.1", "por.1", "arg.1", "ned.1", "col.1", "usa.1", "fifa.friendly":
            return false
        case "uefa.super_cup":
            return true
        case "fifa.world", "uefa.euro", "conmebol.america", "fifa.cwc", "concacaf.gold", "caf.nations", "afc.asian.cup":
            return footballIsSingleMatchKnockoutContext(match)
        case "uefa.champions", "uefa.europa":
            return footballIsFinalContext(match) || footballIsSecondLegContext(match)
        case "conmebol.libertadores":
            return footballIsFinalContext(match) || footballIsSecondLegContext(match)
        default:
            return false
        }
    }

    nonisolated private static func footballIsSingleMatchKnockoutContext(_ match: FootballFixtureMatch) -> Bool {
        guard !footballContainsAnyContextToken(match, tokens: ["group", "regular", "league", "season", "matchday"]) else {
            return false
        }

        return footballContainsAnyContextToken(
            match,
            tokens: ["round", "quarterfinal", "quarterfinals", "quarter", "semifinal", "semifinals", "semi", "final", "finals", "knockout"]
        )
    }

    nonisolated private static func footballIsSecondLegContext(_ match: FootballFixtureMatch) -> Bool {
        let normalizedNote = footballNormalizedStatusText(match.competitionNote ?? "")
        return normalizedNote.contains("2ND LEG")
            || normalizedNote.contains("SECOND LEG")
            || normalizedNote.contains("TIED ON AGGREGATE")
    }

    nonisolated private static func footballIsFinalContext(_ match: FootballFixtureMatch) -> Bool {
        let words = footballContextWords(for: match)
        return words.contains("final") || words.contains("finals")
    }

    nonisolated private static func footballContainsAnyContextToken(
        _ match: FootballFixtureMatch,
        tokens: Set<String>
    ) -> Bool {
        !footballContextWords(for: match).isDisjoint(with: tokens)
    }

    nonisolated private static func footballContextWords(for match: FootballFixtureMatch) -> Set<String> {
        let rawValues = [
            match.competitionStage,
            match.seasonSlug,
            match.competitionNote,
        ]

        return rawValues.reduce(into: Set<String>()) { partialResult, value in
            guard let value else { return }
            let normalized = value
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased()
            let tokens = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            partialResult.formUnion(tokens)
        }
    }

    nonisolated private static func footballGoalValue(_ rawScore: String) -> Int {
        let trimmed = rawScore.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed) ?? 0
    }

    nonisolated private static func footballEffectiveStartDate(for match: FootballFixtureMatch) -> Date {
        match.actualStartDate ?? match.startDate
    }

    nonisolated private static func footballScoresAreLevel(_ match: FootballFixtureMatch) -> Bool {
        footballGoalValue(match.homeScore) == footballGoalValue(match.awayScore)
    }

    nonisolated private static func footballLiveMinute(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Int? {
        if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
            return nil
        }

        let normalizedStatus = footballNormalizedStatusText(match.statusText)

        if footballInterruptedStatusBadgeText(from: normalizedStatus) != nil {
            return nil
        }

        if normalizedStatus == "HT" || normalizedStatus.contains("HALF") {
            return 45
        }

        if normalizedStatus.contains("PEN") || normalizedStatus == "PK" {
            return 121
        }

        if normalizedStatus == "ET" || normalizedStatus.contains("EXTRA TIME") {
            return 91
        }

        if let parsed = footballParsedMinute(from: match.statusText) {
            return parsed
        }

        guard match.statusState == .inProgress
            || (match.statusState == .unknown && footballEffectiveStartDate(for: match) <= now) else {
            return nil
        }

        return footballInferredMinuteFromKickoff(for: match, now: now)
    }

    nonisolated private static func footballInterruptedMatchDuration(
        for match: FootballFixtureMatch,
        badgeText: String
    ) -> TimeInterval {
        switch badgeText {
        case "ABN", "CANC.":
            if let minute = footballReportedStatusMinute(for: match) {
                return footballDuration(forReportedMinute: minute)
            }
            return footballRegulationMatchDuration
        case "SUSP.", "POSTP.", "DELAY":
            return footballRegulationMatchDuration
        default:
            return footballRegulationMatchDuration
        }
    }

    nonisolated private static func footballInferredMinuteFromKickoff(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Int? {
        let elapsedSeconds = max(0, now.timeIntervalSince(footballEffectiveStartDate(for: match)))
        let rawMinutes = Int(elapsedSeconds / 60)
        if rawMinutes <= 45 {
            return rawMinutes
        }
        if rawMinutes <= 60 {
            return 45
        }
        return max(46, rawMinutes - 15)
    }

    nonisolated private static func shouldPreferInferredLiveMinute(
        reportedMinute: Int,
        inferredMinute: Int,
        match: FootballFixtureMatch
    ) -> Bool {
        guard match.statusState == .inProgress,
              match.statusReliability == .reported else {
            return false
        }

        guard inferredMinute >= 60 else { return false }
        return inferredMinute - reportedMinute >= 35
    }

    nonisolated private static func footballReportedStatusMinute(for match: FootballFixtureMatch) -> Int? {
        if let parsed = footballParsedMinute(from: match.statusText) {
            return parsed
        }

        guard let statusDetailText = match.statusDetailText else { return nil }
        return footballParsedMinute(from: statusDetailText)
    }

    nonisolated private static func footballDuration(forReportedMinute minute: Int) -> TimeInterval {
        let elapsedMinutes: Int
        if minute <= 45 {
            elapsedMinutes = minute
        } else if minute <= 90 {
            elapsedMinutes = minute + 15
        } else {
            elapsedMinutes = minute + 20
        }

        return TimeInterval(max(15, elapsedMinutes) * 60)
    }

    nonisolated private static func footballParsedMinute(from rawStatusText: String) -> Int? {
        let trimmed = rawStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"(\d{1,3})(?:\+(\d{1,2}))?\s*'"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: trimmed,
                  range: NSRange(trimmed.startIndex..., in: trimmed)
              ) else {
            return nil
        }

        let baseMinute = footballRegexInt(match, in: trimmed, at: 1) ?? 0
        let extraMinute = footballRegexInt(match, in: trimmed, at: 2) ?? 0
        let combinedMinute = baseMinute + extraMinute
        return combinedMinute > 0 ? combinedMinute : nil
    }

    nonisolated private static func footballInterruptedStatusBadgeText(from normalizedStatus: String) -> String? {
        if normalizedStatus.contains("ABANDONED") || normalizedStatus.contains("ABN") {
            return "ABN"
        }

        if normalizedStatus.contains("SUSPENDED") || normalizedStatus.contains("SUSP") {
            return "SUSP."
        }

        if normalizedStatus.contains("POSTPONED") || normalizedStatus.contains("POSTP") {
            return "POSTP."
        }

        if normalizedStatus.contains("DELAYED") || normalizedStatus.contains("DELAY") {
            return "DELAY"
        }

        if normalizedStatus.contains("CANCELED") || normalizedStatus.contains("CANCELLED") {
            return "CANC."
        }

        return nil
    }

    nonisolated private static func footballRegexInt(_ result: NSTextCheckingResult, in text: String, at index: Int) -> Int? {
        guard index < result.numberOfRanges else { return nil }
        let range = result.range(at: index)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: text) else {
            return nil
        }
        return Int(text[swiftRange])
    }

    nonisolated private static func footballLooksLikeMinuteStatus(_ rawStatusText: String) -> Bool {
        footballParsedMinute(from: rawStatusText) != nil
    }

    nonisolated private static func footballNormalizedStatusText(_ rawStatusText: String) -> String {
        rawStatusText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
    }
}
