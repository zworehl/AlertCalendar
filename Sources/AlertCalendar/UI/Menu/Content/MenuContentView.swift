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
        VStack(alignment: .leading, spacing: 12) {
            headerView

            if monitor.isInitialLoadInProgress {
                initialLoadingSection
            } else {
                if !shouldUseSplitDropdownLayout && !filteredAlertDescriptions.isEmpty {
                    alertBannerSection
                }

                if shouldUseSplitDropdownLayout {
                    HStack(alignment: .top, spacing: splitColumnSpacing) {
                        contextualActionSection
                            .frame(width: splitActionsColumnWidth, alignment: .topLeading)

                        VStack(alignment: .leading, spacing: 8) {
                            if !filteredAlertDescriptions.isEmpty {
                                alertBannerSection
                            }

                            upcomingSection
                        }
                        .frame(width: splitQueueColumnWidth, alignment: .topLeading)
                    }
                } else {
                    if !displayedContextualActionItems.isEmpty {
                        contextualActionSection
                    }

                    upcomingSection
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
            minWidth: dropdownMinimumWidth,
            idealWidth: shouldUseSplitDropdownLayout ? dropdownPreferredWidth : nil,
            maxWidth: shouldUseSplitDropdownLayout ? dropdownPreferredWidth : dropdownMinimumWidth,
            alignment: .leading
        )
        .id(shouldUseSplitDropdownLayout ? "split-dropdown" : "single-dropdown")
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
