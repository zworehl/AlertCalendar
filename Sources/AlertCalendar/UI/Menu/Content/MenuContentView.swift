import AppKit
import CoreLocation
import MapKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var monitor: CalendarMonitor
    @Environment(\.openWindow) var openWindow
    let kindFilter: CalendarItemKind?
    let headerTitle: String

    @State var dropdownReferenceDate = AlertCalendarClock.nowRoundedToSecond()
    @State var splitUpcomingPanelHeight: CGFloat = 0
    @State var splitRightColumnHeight: CGFloat = 0
    @State var splitContextualCompactPanelHeight: CGFloat = 0
    @State var splitContextualPanelMeasurementKey = ""
    let dropdownOuterPadding: CGFloat = 12
    let upcomingListMaxHeight: CGFloat = 360
    let splitDropdownMaxColumnHeight: CGFloat = 520
    let minimumSingleColumnDropdownWidth: CGFloat = 260
    let minimumContextualPanelDropdownWidth: CGFloat = 360
    let splitColumnSpacing: CGFloat = 12
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
        let resolvedDropdownWidth = snapshot.dropdownMinimumWidth
        let shouldShowLoading = monitor.isInitialLoadInProgress
            || shouldShowTransientRefreshLoading(snapshot: snapshot)

        VStack(alignment: .leading, spacing: 12) {
            headerView

            if shouldShowLoading {
                initialLoadingSection
            } else {
                if !snapshot.shouldUseSplitDropdownLayout && !snapshot.filteredAlertDescriptions.isEmpty {
                    alertBannerSection(alertDescriptions: snapshot.filteredAlertDescriptions)
                }

                if snapshot.shouldUseSplitDropdownLayout {
                    HStack(alignment: .top, spacing: splitColumnSpacing) {
                        contextualActionSection(snapshot: snapshot)

                        VStack(alignment: .leading, spacing: 8) {
                            if !snapshot.filteredAlertDescriptions.isEmpty {
                                alertBannerSection(alertDescriptions: snapshot.filteredAlertDescriptions)
                            }

                            upcomingSection(snapshot: snapshot)
                        }
                        .frame(width: upcomingPanelOuterWidth(snapshot: snapshot), alignment: .topLeading)
                        .clipped()
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: SplitRightColumnHeightPreferenceKey.self,
                                    value: splitUpcomingPanelHeight > 0 ? proxy.size.height : 0
                                )
                            }
                        )
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
        .fixedSize(horizontal: false, vertical: !snapshot.shouldUseSplitDropdownLayout)
        .frame(width: resolvedDropdownWidth, alignment: .leading)
        .clipped()
        .onAppear {
            prepareDropdownPresentation()
        }
        .onPreferenceChange(SplitUpcomingPanelHeightPreferenceKey.self) { height in
            guard abs(splitUpcomingPanelHeight - height) > 0.5 else { return }
            splitUpcomingPanelHeight = height
        }
        .onPreferenceChange(SplitRightColumnHeightPreferenceKey.self) { height in
            guard snapshot.shouldUseSplitDropdownLayout,
                  height > 0,
                  abs(splitRightColumnHeight - height) > 0.5 else {
                return
            }
            splitRightColumnHeight = height
        }
        .onPreferenceChange(SplitContextualPanelMeasurementPreferenceKey.self) { measurement in
            let measurementKey = snapshot.contextualPanelMeasurementKey
            guard snapshot.shouldUseSplitDropdownLayout,
                  measurement.key == measurementKey,
                  measurement.height > 0,
                  (splitContextualPanelMeasurementKey != measurementKey
                      || splitContextualCompactPanelHeight <= 0) else {
                return
            }
            splitContextualPanelMeasurementKey = measurementKey
            splitContextualCompactPanelHeight = measurement.height
        }
    }
}
