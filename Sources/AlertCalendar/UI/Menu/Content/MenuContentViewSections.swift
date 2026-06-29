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

    func calendarSectionContainer<Content: View>(
        height: CGFloat? = nil,
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
        .frame(height: height, alignment: .topLeading)
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

    var dropdownMinimumWidth: CGFloat {
        if shouldUseSplitDropdownLayout {
            return dropdownPreferredWidth
        }

        return max(
            minimumSingleColumnDropdownWidth,
            singleColumnContextualMinimumWidth,
            singleColumnQueueMinimumWidth
        )
    }

    var dropdownPreferredWidth: CGFloat {
        let contentWidth = splitActionsColumnWidth + splitQueueColumnWidth + splitColumnSpacing
        return contentWidth + (dropdownOuterPadding * 2)
    }

    var singleColumnContextualMinimumWidth: CGFloat {
        displayedContextualActionItems.reduce(minimumSingleColumnDropdownWidth) { partialResult, item in
            max(partialResult, contextualCardMinimumWidth(for: item))
        }
    }

    var singleColumnQueueMinimumWidth: CGFloat {
        queueItemsForActions.reduce(minimumSingleColumnDropdownWidth) { partialResult, item in
            max(partialResult, queueItemMinimumWidth(for: item))
        }
    }

    var splitDropdownColumnHeightLimit: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 960
        return min(splitDropdownMaxColumnHeight, max(360, screenHeight * 0.62))
    }

    func splitPanelHeight(measuredHeight: CGFloat, snapshot: LayoutSnapshot) -> CGFloat? {
        guard snapshot.shouldUseSplitDropdownLayout else { return nil }
        guard measuredHeight > 0 else { return nil }
        return min(splitDropdownColumnHeightLimit, measuredHeight)
    }

    func contextualSplitPanelHeight(snapshot: LayoutSnapshot) -> CGFloat? {
        splitPanelHeight(measuredHeight: splitContextualPanelHeight, snapshot: snapshot)
    }

    func upcomingSplitPanelHeight(snapshot: LayoutSnapshot) -> CGFloat? {
        splitPanelHeight(measuredHeight: splitUpcomingPanelHeight, snapshot: snapshot)
    }

    func shouldScrollContextualSplitPanel(snapshot: LayoutSnapshot) -> Bool {
        guard snapshot.shouldUseSplitDropdownLayout,
              let contextualSplitPanelHeight = contextualSplitPanelHeight(snapshot: snapshot) else {
            return false
        }

        return splitContextualPanelHeight > contextualSplitPanelHeight + 0.5
    }

    func shouldScrollUpcomingSplitPanel(snapshot: LayoutSnapshot) -> Bool {
        guard snapshot.shouldUseSplitDropdownLayout,
              let upcomingSplitPanelHeight = upcomingSplitPanelHeight(snapshot: snapshot) else {
            return false
        }

        return splitUpcomingPanelHeight > upcomingSplitPanelHeight + 0.5
    }

    var shouldUseSplitDropdownLayout: Bool {
        !footballContextualActionItems.isEmpty && !queueItemsForSplitLayout.isEmpty
    }

    var sharedContextualFootballMatches: [FootballFixtureMatch]? {
        guard !displayedContextualActionItems.isEmpty else { return nil }

        let footballMatches = displayedContextualActionItems.compactMap(\.footballMatch)
        guard footballMatches.count == displayedContextualActionItems.count else { return nil }

        return footballMatches
    }

    var sharedContextualFootballCompetitionTitle: String? {
        guard let sharedContextualFootballMatches else { return nil }
        return FootballFixtureFormatter.sharedCompetitionTitle(for: sharedContextualFootballMatches)
    }

    var sharedContextualFootballCompetitionLogoPath: String? {
        guard sharedContextualFootballCompetitionTitle != nil else { return nil }
        return displayedContextualActionItems.first?.footballMenuBarDisplay?.competitionLocalLogoPath
    }

    var sharedContextualFootballCompetitionLogoURL: URL? {
        guard let sharedContextualFootballMatches,
              sharedContextualFootballCompetitionTitle != nil else {
            return nil
        }

        return sharedContextualFootballMatches.first?.competitionLogoURL
    }

    var contextualSharedCompetitionHeader: some View {
        contextualSharedCompetitionHeader(
            title: sharedContextualFootballCompetitionTitle ?? "",
            localPath: sharedContextualFootballCompetitionLogoPath,
            remoteURL: sharedContextualFootballCompetitionLogoURL
        )
    }

    func contextualSharedCompetitionHeader(snapshot: LayoutSnapshot) -> some View {
        contextualSharedCompetitionHeader(
            title: snapshot.sharedContextualFootballCompetitionTitle ?? "",
            localPath: snapshot.sharedContextualFootballCompetitionLogoPath,
            remoteURL: snapshot.sharedContextualFootballCompetitionLogoURL
        )
    }

    private func contextualSharedCompetitionHeader(
        title: String,
        localPath: String?,
        remoteURL: URL?
    ) -> some View {
        HStack(spacing: 6) {
            FootballCompetitionLogoView(
                localPath: localPath,
                remoteURL: remoteURL,
                placeholderSymbolSize: 11
            )

            Text("All listed matches are from \(title)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    var contextualSharedCompetitionIsActive: Bool {
        sharedContextualFootballCompetitionTitle != nil
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
