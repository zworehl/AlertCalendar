import AppKit
import CoreLocation
import MapKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var monitor: CalendarMonitor
    @Environment(\.openWindow) var openWindow
    let kindFilter: CalendarItemKind?
    let headerTitle: String

    @State var splitContextualPanelHeight: CGFloat = 0
    @State var splitUpcomingPanelHeight: CGFloat = 0
    let dropdownOuterPadding: CGFloat = 12
    let upcomingListMaxHeight: CGFloat = 360
    let splitDropdownMaxColumnHeight: CGFloat = 760
    let minimumSingleColumnDropdownWidth: CGFloat = 260
    let splitColumnSpacing: CGFloat = 12
    let splitActionsColumnWidth: CGFloat = 468
    let splitQueueColumnWidth: CGFloat = 336
    let panelHorizontalPadding: CGFloat = 8
    let panelTopPadding: CGFloat = 8
    let panelBottomPadding: CGFloat = 8
    let splitPanelBottomPadding: CGFloat = 8

    var settings: AppSettings {
        monitor.currentSettings
    }

    var body: some View {
        let snapshot = layoutSnapshot

        VStack(alignment: .leading, spacing: 12) {
            headerView

            if monitor.isInitialLoadInProgress {
                initialLoadingSection
            } else {
                if !snapshot.shouldUseSplitDropdownLayout && !snapshot.filteredAlertDescriptions.isEmpty {
                    alertBannerSection(alertDescriptions: snapshot.filteredAlertDescriptions)
                }

                if snapshot.shouldUseSplitDropdownLayout {
                    HStack(alignment: .top, spacing: splitColumnSpacing) {
                        contextualActionSection(snapshot: snapshot)
                            .frame(width: splitActionsColumnWidth, alignment: .topLeading)

                        VStack(alignment: .leading, spacing: 8) {
                            if !snapshot.filteredAlertDescriptions.isEmpty {
                                alertBannerSection(alertDescriptions: snapshot.filteredAlertDescriptions)
                            }

                            upcomingSection(snapshot: snapshot)
                        }
                        .frame(width: splitQueueColumnWidth, alignment: .topLeading)
                    }
                } else {
                    if !snapshot.displayedContextualActionItems.isEmpty {
                        contextualActionSection(snapshot: snapshot)
                    }

                    upcomingSection(snapshot: snapshot)
                }
            }

            HStack {
                if monitor.hasSkippedItems() {
                    Button("Restore Skipped") {
                        monitor.restoreSkippedItems()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if shouldShowSilenceButton {
                    Button("Silence Alert") {
                        monitor.silenceCurrentAlert()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
            }
        }
        .padding(dropdownOuterPadding)
        .background(Color(nsColor: .windowBackgroundColor))
        .fixedSize(horizontal: false, vertical: true)
        .frame(
            minWidth: snapshot.dropdownMinimumWidth,
            idealWidth: snapshot.shouldUseSplitDropdownLayout ? dropdownPreferredWidth : nil,
            maxWidth: snapshot.shouldUseSplitDropdownLayout ? dropdownPreferredWidth : snapshot.dropdownMinimumWidth,
            alignment: .leading
        )
        .id(snapshot.shouldUseSplitDropdownLayout ? "split-dropdown" : "single-dropdown")
        .onPreferenceChange(SplitContextualPanelHeightPreferenceKey.self) { height in
            guard abs(splitContextualPanelHeight - height) > 0.5 else { return }
            splitContextualPanelHeight = height
        }
        .onPreferenceChange(SplitUpcomingPanelHeightPreferenceKey.self) { height in
            guard abs(splitUpcomingPanelHeight - height) > 0.5 else { return }
            splitUpcomingPanelHeight = height
        }
    }
}
