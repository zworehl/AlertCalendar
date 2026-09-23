import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    var headerView: some View {
        let isRefreshing = monitor.isInitialLoadInProgress || isManualDropdownRefreshInProgress

        return HStack(alignment: .center, spacing: 4) {
            Text(headerTitle)
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            ZStack {
                ProgressView()
                    .controlSize(.small)
                    .hidden()

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Refreshing Alert Calendar")
            .accessibilityHidden(!isRefreshing)

            Button {
                refreshDropdownManually()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(MenuToolbarButtonStyle())
            .allowsHitTesting(!isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help(isRefreshing ? "Refreshing" : "Refresh")

            Button {
                openSettingsWindowFromDropdown()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(MenuToolbarButtonStyle())
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings")

            Menu {
                if monitor.hasSkippedItems() {
                    Button {
                        monitor.restoreSkippedItems()
                    } label: {
                        Label("Restore Skipped Items", systemImage: "arrow.uturn.backward")
                    }
                }

                if shouldShowSilenceButton {
                    Button {
                        monitor.silenceCurrentAlert()
                    } label: {
                        Label("Silence Current Alert", systemImage: "bell.slash")
                    }
                }

                if monitor.hasSkippedItems() || shouldShowSilenceButton {
                    Divider()
                }

                Button {
                    openAboutPanelFromDropdown()
                } label: {
                    Label("About Alert Calendar", systemImage: "info.circle")
                }

                Divider()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit Alert Calendar", systemImage: "power")
                }
                .keyboardShortcut("q", modifiers: .command)
            } label: {
                Label("More Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .font(.system(size: MenuContentNativeMetrics.toolbarSymbolSize, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(
                        width: MenuContentNativeMetrics.toolbarButtonSize,
                        height: MenuContentNativeMetrics.toolbarButtonSize
                    )
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More Actions")
        }
        .frame(minHeight: MenuContentNativeMetrics.toolbarButtonSize)
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

    func refreshDropdownManually() {
        guard !monitor.isInitialLoadInProgress,
              !isManualDropdownRefreshInProgress else {
            return
        }

        isManualDropdownRefreshInProgress = true
        Task { @MainActor in
            let startedAt = Date()
            await monitor.enqueueRefreshAndWait(reason: .manual)

            let remainingPresentationTime = max(0, 0.5 - Date().timeIntervalSince(startedAt))
            if remainingPresentationTime > 0 {
                try? await Task.sleep(
                    nanoseconds: UInt64(remainingPresentationTime * 1_000_000_000)
                )
            }
            isManualDropdownRefreshInProgress = false
        }
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
            RoundedRectangle(
                cornerRadius: MenuContentNativeMetrics.sectionCornerRadius,
                style: .continuous
            )
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.64))
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

    func openAboutPanelFromDropdown() {
        let sourceWindow = NSApp.keyWindow
        sourceWindow?.orderOut(nil)

        DispatchQueue.main.async {
            NSRunningApplication.current.activate(
                options: [.activateAllWindows, .activateIgnoringOtherApps]
            )
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
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
