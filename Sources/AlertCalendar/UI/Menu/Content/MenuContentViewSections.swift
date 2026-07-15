import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    var alertBannerSection: some View {
        alertBannerSection(alertDescriptions: filteredAlertDescriptions)
    }

    func alertBannerSection(alertDescriptions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(alertDescriptions, id: \.self) { alertText in
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 20, height: 20, alignment: .center)

                    Text(alertText)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
    }

    var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(headerTitle)
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            if monitor.isInitialLoadInProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                monitor.refreshNow(reason: .manual)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh")

            Button {
                openSettingsWindowFromDropdown()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")

            if monitor.hasSkippedItems() {
                Button {
                    monitor.restoreSkippedItems()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Restore Skipped")
            }

            if shouldShowSilenceButton {
                Button {
                    monitor.silenceCurrentAlert()
                } label: {
                    Image(systemName: "bell.slash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Silence Alert")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit")
        }
    }

    var initialLoadingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("LOADING")
            calendarSectionContainer {
                HStack(alignment: .center, spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loading upcoming items")
                            .font(.subheadline.weight(.semibold))

                        Text("Checking calendars, reminders, and feeds. \(monitor.calendarAccessDescription)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }
        }
    }

    func shouldShowTransientRefreshLoading(snapshot: LayoutSnapshot) -> Bool {
        guard !monitor.isInitialLoadInProgress,
              monitor.refreshDiagnostics.isInProgress,
              shouldExpectCalendarBackedItemsDuringRefresh,
              snapshot.displayedContextualActionItems.isEmpty,
              snapshot.queueItemsForActions.isEmpty || Self.containsOnlyAstronomyItems(snapshot.queueItemsForActions) else {
            return false
        }

        return true
    }

    var shouldExpectCalendarBackedItemsDuringRefresh: Bool {
        (settings.includeEvents && monitor.hasEventsAccess)
            || (settings.includeReminders && monitor.hasRemindersAccess)
            || !monitor.managedFootballMatchIDs.isEmpty
            || !monitor.managedFootballMatches.isEmpty
            || monitor.footballLiveAndNextDaySection.isLoading
            || monitor.footballMenuSections.contains { $0.isLoading }
    }

    nonisolated static func containsOnlyAstronomyItems(_ items: [UpcomingItem]) -> Bool {
        !items.isEmpty && items.allSatisfy { AstronomyMoment(eventTitle: $0.title) != nil }
    }

    func calendarSectionContainer<Content: View>(
        height: CGFloat? = nil,
        minimumHeight: CGFloat? = nil,
        bottomPadding: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let resolvedBottomPadding = bottomPadding ?? panelBottomPadding
        return VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, panelHorizontalPadding)
        .padding(.top, panelTopPadding)
        .padding(.bottom, resolvedBottomPadding)
        .frame(height: height, alignment: .topLeading)
        .frame(minHeight: minimumHeight, alignment: .topLeading)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
    }

    func openSettingsWindowFromDropdown() {
        let sourceWindow = NSApp.keyWindow
        let appDelegate = NSApp.delegate as? AppDelegate

        if let appDelegate {
            appDelegate.prepareForSettingsPresentation()
        } else {
            _ = NSApplication.shared.setActivationPolicy(.regular)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        if sourceWindow?.identifier != NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID) {
            sourceWindow?.orderOut(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            openWindow(id: WindowMetadata.preferencesID)
        }
    }

    enum FootballContextualContentLevel {
        case statsAndGoals
        case goalsOnly
        case compact

        var showsStats: Bool {
            switch self {
            case .statsAndGoals:
                return true
            case .goalsOnly, .compact:
                return false
            }
        }

        var showsGoalScorers: Bool {
            switch self {
            case .statsAndGoals, .goalsOnly:
                return true
            case .compact:
                return false
            }
        }
    }

    enum FootballContextualScorePlacement {
        case headline
        case stats
        case goalScorers
    }

    var contextualFootballContentLevel: FootballContextualContentLevel {
        Self.contextualFootballContentLevel(for: displayedContextualActionItems.count)
    }

    nonisolated static func contextualFootballContentLevel(for itemCount: Int) -> FootballContextualContentLevel {
        switch max(1, itemCount) {
        case 1:
            return .statsAndGoals
        case 2, 3:
            return .goalsOnly
        default:
            return .compact
        }
    }

    nonisolated static func shouldShowContextualFootballGoalScorers(for itemCount: Int) -> Bool {
        contextualFootballContentLevel(for: itemCount).showsGoalScorers
    }

    nonisolated static func shouldShowStandaloneContextualFootballOutcomeProbabilities(
        for match: FootballFixtureMatch,
        itemCount: Int
    ) -> Bool {
        let contentLevel = contextualFootballContentLevel(for: itemCount)
        if contentLevel.showsStats && match.statusState != .scheduled {
            return false
        }
        return itemCount <= 2
    }

    nonisolated static func footballContextualScorePlacement(
        for match: FootballFixtureMatch,
        itemCount: Int
    ) -> FootballContextualScorePlacement {
        guard match.hasVisibleScore else { return .headline }

        let contentLevel = contextualFootballContentLevel(for: itemCount)
        if contentLevel.showsStats && match.statusState != .scheduled {
            return .stats
        }
        if !contentLevel.showsStats && contentLevel.showsGoalScorers && match.totalGoals > 0 {
            return .goalScorers
        }
        return .headline
    }

    nonisolated static func shouldUseExpandedContextualFootballHeader(
        for match: FootballFixtureMatch,
        itemCount: Int
    ) -> Bool {
        itemCount <= 3 && match.hasVisibleScore
    }

    nonisolated static func shouldShowGoalScorersSectionHeader(for itemCount: Int) -> Bool {
        itemCount == 2 || itemCount == 3
    }

}
