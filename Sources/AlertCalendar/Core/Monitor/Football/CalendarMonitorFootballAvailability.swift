import Foundation

struct FootballCompetitionAvailabilityRequest: Sendable {
    let window: FootballCompetitionAvailabilityWindow
    let lookbackDays: Int
    let lookaheadDays: Int
    let force: Bool
}

extension CalendarMonitor {
    func refreshFootballCompetitionAvailability(lookbackDays: Int, lookaheadDays: Int, force: Bool = false) async {
        await restorePersistentCachesIfNeeded()
        ensureFootballCompetitionSections()
        let lookbackDays = AppSettingsRules.normalizedFootballWindowDays(lookbackDays)
        let lookaheadDays = AppSettingsRules.normalizedFootballWindowDays(lookaheadDays)
        let request = FootballCompetitionAvailabilityRequest(
            window: FootballCompetitionAvailabilityWindow(
                now: fixedSecondNow(),
                lookbackDays: lookbackDays,
                lookaheadDays: lookaheadDays
            ),
            lookbackDays: lookbackDays,
            lookaheadDays: lookaheadDays,
            force: force || (footballState.pendingAvailabilityRequest?.force ?? false)
        )
        footballState.lastAvailabilityRequest = request
        footballState.pendingAvailabilityRequest = request
        if footballState.availabilityRefreshTask == nil {
            footballState.availabilityRefreshTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while let request = self.footballState.pendingAvailabilityRequest {
                    self.footballState.pendingAvailabilityRequest = nil
                    await self.loadFootballCompetitionAvailability(request)
                }
                self.footballState.availabilityRefreshTask = nil
            }
        }
        await footballState.availabilityRefreshTask?.value
    }

    func refreshLastFootballCompetitionAvailability(force: Bool) async {
        guard let request = footballState.lastAvailabilityRequest else { return }
        await refreshFootballCompetitionAvailability(
            lookbackDays: request.lookbackDays, lookaheadDays: request.lookaheadDays, force: force
        )
    }

    private func loadFootballCompetitionAvailability(_ request: FootballCompetitionAvailabilityRequest) async {
        let now = fixedSecondNow()
        let competitions = FootballCompetitionPreset.menuPresets.filter { preset in
            request.force || !(footballState.availabilityBySlug[preset.slug]?.isFresh(for: request.window, now: now) ?? false)
        }
        guard !competitions.isEmpty else { return }
        for competition in competitions {
            updateFootballCompetitionSection(competition.id) { section in
                FootballMenuCompetitionSection(
                    competition: competition, matches: section.matches, errorMessage: section.errorMessage,
                    isLoading: true, hasLoaded: section.hasLoaded, checkedWindow: section.checkedWindow
                )
            }
        }

        // Checking the catalogue never enriches teams, downloads images, or adds Calendar events.
        // Keep the number of simultaneous competitions bounded even for the full 180-day window.
        let client = footballClient
        await withTaskGroup(of: (FootballCompetitionPreset, FootballFixtureLoadResult).self) { group in
            var iterator = competitions.makeIterator()
            func enqueue(_ competition: FootballCompetitionPreset) {
                group.addTask {
                    do {
                        let ranges = FootballDataAPIClient.scoreboardDateRanges(
                            start: request.window.start, end: request.window.end, calendar: .autoupdatingCurrent
                        ).map { FootballScoreboardDateRange(start: $0.0, end: $0.1) }
                        let result = try await client.fetchFixtureLoadResult(
                            for: [competition], dateRangesByCompetitionSlug: [competition.slug: ranges],
                            enrichTeams: false, forceRefresh: request.force, healthScope: "availability"
                        )
                        return (competition, result)
                    } catch {
                        return (competition, FootballFixtureLoadResult(failures: [FootballFixtureLoadFailure(
                            competitionSlug: competition.slug,
                            range: FootballScoreboardDateRange(start: request.window.start, end: request.window.end),
                            reason: FootballDataAPIClient.fixtureFailureDescription(error)
                        )]))
                    }
                }
            }
            for _ in 0..<3 {
                if let competition = iterator.next() { enqueue(competition) }
            }
            while let (competition, result) = await group.next() {
                // Each chunk may have succeeded after an earlier chunk failed.
                // Publish the combined sweep so a later success cannot clear that failure.
                await DataRefreshHealth.shared.record(
                    source: "football.availability.\(competition.slug)", title: competition.title,
                    error: result.warning, at: result.failures.map(\.attemptedAt).max() ?? Date()
                )
                applyFootballCompetitionAvailability(result, competition: competition, window: request.window, now: now)
                if result.failures.isEmpty {
                    await ExternalFeedMetrics.shared.recordAppliedData(source: "football.snapshot", at: now)
                }
                if let competition = iterator.next() { enqueue(competition) }
            }
        }
        await persistFootballCompetitionAvailability()
    }

    func applyFootballCompetitionAvailability(
        _ result: FootballFixtureLoadResult,
        competition: FootballCompetitionPreset,
        window: FootballCompetitionAvailabilityWindow,
        now: Date
    ) {
        let previous = footballMenuSections.first { $0.id == competition.id }
        let previousByID = Dictionary((previous?.matches ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
        let refreshedMatches = result.restoringCachedMatches(previous?.matches ?? []).map { match in
            Self.footballMatchPreservingKnownTimingContext(
                match, previousMatch: footballMatchesByID[match.id] ?? previousByID[match.id]
            )
        }
        let endExclusive = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: window.end) ?? window.end
        // A narrow availability check must not discard a wider, enriched detail load.
        let outsideWindow = (previous?.matches ?? []).filter {
            $0.startDate < window.start || $0.startDate >= endExclusive
        }
        let matches = FootballFixtureLoadResult(matches: refreshedMatches + outsideWindow).restoringCachedMatches([])
        if let confirmed = FootballCompetitionAvailability.confirmed(
            from: FootballFixtureLoadResult(matches: matches, failures: result.failures, availablePageCount: result.availablePageCount),
            competitionSlug: competition.slug, window: window, now: now
        ) {
            footballState.availabilityBySlug[competition.slug] = confirmed
        }
        updateFootballCompetitionSection(competition.id) { section in
            FootballMenuCompetitionSection(
                competition: competition, matches: matches, errorMessage: result.warning,
                isLoading: false, hasLoaded: section.hasLoaded || result.availablePageCount > 0 || !matches.isEmpty,
                checkedWindow: section.checkedWindow.flatMap { $0.contains(window) ? $0 : nil } ?? window
            )
        }
    }
}
