import AppKit
import CoreLocation
import EventKit
import Foundation

extension CalendarMonitor {
    nonisolated static let footballAutoAddRefreshInterval: TimeInterval = 3 * 60 * 60

    nonisolated static func normalizedFootballAutoAddCompetitionSlugs(_ slugs: [String]) -> [String] {
        let requestedSlugs = Set(
            slugs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        return FootballCompetitionPreset.menuPresets
            .map(\.slug)
            .filter { requestedSlugs.contains($0) }
    }

    nonisolated static func footballMatchesEligibleForAutoAdd(
        _ matches: [FootballFixtureMatch],
        enabledCompetitionSlugs: Set<String>,
        managedMatchIDs: Set<String>,
        now: Date
    ) -> [FootballFixtureMatch] {
        deduplicatedFootballMatches(matches)
            .filter { match in
                guard enabledCompetitionSlugs.contains(match.competitionSlug) else { return false }
                guard !managedMatchIDs.contains(match.id) else { return false }
                guard !FootballFixtureFormatter.hasUnknownParticipants(in: match) else { return false }

                switch match.statusState {
                case .inProgress:
                    return true
                case .scheduled, .unknown:
                    return match.startDate >= now || match.statusReliability != .reported
                case .finished:
                    return false
                }
            }
            .map { match in
                (match: match, priority: footballFixtureSortPriority(for: match, now: now))
            }
            .sorted { $0.priority < $1.priority }
            .map(\.match)
    }

    func footballAutoAddCompetitionSlugs() -> Set<String> {
        let normalizedSlugs = Self.normalizedFootballAutoAddCompetitionSlugs(
            defaults.stringArray(forKey: DefaultsKeys.footballAutoAddCompetitionSlugs) ?? []
        )
        return Set(normalizedSlugs)
    }

    func setFootballAutoAddCompetitionSlugs(_ slugs: Set<String>) {
        let normalizedSlugs = Self.normalizedFootballAutoAddCompetitionSlugs(Array(slugs))
        guard normalizedSlugs != (defaults.stringArray(forKey: DefaultsKeys.footballAutoAddCompetitionSlugs) ?? []) else {
            return
        }
        defaults.set(normalizedSlugs, forKey: DefaultsKeys.footballAutoAddCompetitionSlugs)
    }

    func setFootballAutoAddEnabled(_ isEnabled: Bool, for competition: FootballCompetitionPreset) {
        var slugs = footballAutoAddCompetitionSlugs()
        if isEnabled {
            slugs.insert(competition.slug)
        } else {
            slugs.remove(competition.slug)
        }
        setFootballAutoAddCompetitionSlugs(slugs)
    }

    func syncAutoAddedFootballMatchesIfNeeded(now: Date, force: Bool = false) async {
        guard hasEventsAccess else { return }
        let enabledSlugs = footballAutoAddCompetitionSlugs()
        guard !enabledSlugs.isEmpty else { return }
        guard force || CalendarMonitorTime.hasElapsed(
            since: lastFootballAutoAddRefreshDate,
            now: now,
            interval: Self.footballAutoAddRefreshInterval
        ) else {
            return
        }

        let presets = FootballCompetitionPreset.menuPresets.filter { enabledSlugs.contains($0.slug) }
        guard !presets.isEmpty else { return }

        lastFootballAutoAddRefreshDate = now
        do {
            let calendar = Calendar(identifier: .gregorian)
            let dayStart = calendar.startOfDay(for: now)
            let dateRangesBySlug = Dictionary(uniqueKeysWithValues: presets.map { preset in
                let end = calendar.date(byAdding: .day, value: preset.lookaheadDays, to: dayStart) ?? dayStart
                let ranges = FootballDataAPIClient.scoreboardDateRanges(
                    start: dayStart,
                    end: end,
                    calendar: calendar
                ).map { FootballScoreboardDateRange(start: $0.0, end: $0.1) }
                return (preset.slug, ranges)
            })
            let fetchedMatches = try await footballClient.fetchMatches(
                for: presets,
                dateRangesByCompetitionSlug: dateRangesBySlug
            )
            let refreshedMatches = await footballClient.refreshStatusesIfNeeded(for: fetchedMatches)
            let resolvedMatches = matchesPreservingKnownTimingContext(refreshedMatches)
            await cacheFootballMatches(resolvedMatches)
            updateFootballCompetitionSectionsAfterAutoAddRefresh(
                presets: presets,
                matches: resolvedMatches,
                now: now
            )
            await autoAddFootballMatches(resolvedMatches, enabledCompetitionSlugs: enabledSlugs, now: now)
        } catch {
            return
        }
    }

    func autoAddFootballMatches(
        _ matches: [FootballFixtureMatch],
        enabledCompetitionSlugs: Set<String>? = nil,
        now: Date
    ) async {
        let slugs = enabledCompetitionSlugs ?? footballAutoAddCompetitionSlugs()
        guard !slugs.isEmpty else { return }

        let eligibleMatches = Self.footballMatchesEligibleForAutoAdd(
            matches,
            enabledCompetitionSlugs: slugs,
            managedMatchIDs: managedFootballMatchIDs,
            now: now
        )
        guard !eligibleMatches.isEmpty else { return }
        guard resolvedFootballTargetCalendar() != nil else {
            calendarAccessDescription = "Choose a writable event calendar before auto-adding fixtures."
            return
        }

        for match in eligibleMatches where !managedFootballMatchIDs.contains(match.id) {
            let didAdd = await addFootballMatchToCalendar(match)
            if didAdd {
                queueFootballAutoAddNotification(for: match, now: now)
            }
        }
    }

    func updateFootballCompetitionSectionsAfterAutoAddRefresh(
        presets: [FootballCompetitionPreset],
        matches: [FootballFixtureMatch],
        now: Date
    ) {
        ensureFootballCompetitionSections()
        let matchesByCompetitionSlug = Dictionary(grouping: matches, by: \.competitionSlug)

        for preset in presets {
            let sectionMatches = Self.resolvedFootballSectionMatches(
                matchesByCompetitionSlug[preset.slug] ?? [],
                cachedMatchesByID: footballMatchesByID,
                now: now
            )
            updateFootballCompetitionSection(preset.id) { _ in
                FootballMenuCompetitionSection(
                    competition: preset,
                    matches: sectionMatches,
                    errorMessage: nil,
                    isLoading: false,
                    hasLoaded: true
                )
            }
        }
    }
}
