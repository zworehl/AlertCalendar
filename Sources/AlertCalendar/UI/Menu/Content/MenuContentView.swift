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
    @State var isDropdownVisible = false
    @State var dropdownAvailableSize = MenuDropdownScreen.commonAvailableSize(screens: MenuDropdownScreen.connected)
    @State var splitUpcomingPanelHeight: CGFloat = 0
    @State var splitRightColumnHeight: CGFloat = 0
    @State var splitContextualCompactPanelHeight: CGFloat = 0
    @State var splitSummaryPanelHeight: CGFloat = 0
    @State var splitContextualPanelMeasurementKey = ""
    @State var expandedBirthdayGroupIDs: Set<String> = []
    @State var isManualDropdownRefreshInProgress = false
    let dropdownOuterPadding: CGFloat = 12
    let upcomingListMaxHeight: CGFloat = 360
    let splitDropdownMaxColumnHeight: CGFloat = 720
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
        let summaryRequest = agendaSummaryRequest(snapshot: snapshot)
        let summaryPresentationAction = AgendaSummaryPresentationAction.resolve(
            isEnabled: settings.showAgendaSummary,
            availability: monitor.agendaSummaryAvailability,
            requestFingerprint: summaryRequest.generationFingerprint(
                usesLinkedPagePreviews: settings.useLinkedPagePreviewsInAgendaSummary
            )
        )
        let resolvedDropdownWidth = snapshot.dropdownMinimumWidth
        let shouldShowLoading = monitor.isInitialLoadInProgress

        VStack(alignment: .leading, spacing: 0) {
            headerView
                .padding(.horizontal, dropdownOuterPadding)
                .padding(.vertical, 7)

            Divider()

            MenuDropdownHeightContainer(
                maximumHeight: max(
                    1,
                    dropdownAvailableSize.height
                        - MenuContentNativeMetrics.toolbarButtonSize - 14 - 1
                )
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if shouldShowLoading {
                        initialLoadingSection
                    } else {
                        if snapshot.shouldUseSplitDropdownLayout {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: splitColumnSpacing) {
                                    contextualActionSection(snapshot: snapshot)
                                    .frame(
                                        width: contextualPanelOuterWidth(snapshot: snapshot),
                                        alignment: .topLeading
                                    )

                                    upcomingSection(snapshot: snapshot)
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

                                dropdownSummarySections(snapshot: snapshot)
                                    .background(
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: SplitSummaryPanelHeightPreferenceKey.self,
                                                value: proxy.size.height
                                            )
                                        }
                                    )
                            }
                        } else {
                            if !snapshot.displayedContextualActionItems.isEmpty {
                                contextualActionSection(snapshot: snapshot)
                            }

                            upcomingSection(snapshot: snapshot)

                            dropdownSummarySections(snapshot: snapshot)
                        }
                    }
                }
                .padding(dropdownOuterPadding)
            }
        }
        .environment(\.controlSize, .small)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: resolvedDropdownWidth, alignment: .leading)
        .modifier(MenuDropdownSurface())
        .background {
            MenuDropdownWindowObserver(isVisible: $isDropdownVisible, availableSize: $dropdownAvailableSize)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onAppear {
            isDropdownVisible = true
            prepareDropdownPresentation()
        }
        .onDisappear {
            isDropdownVisible = false
        }
        .onChange(of: isDropdownVisible) { isVisible in
            guard isVisible else { return }
            prepareDropdownPresentation()
        }
        .task(id: summaryPresentationAction) {
            switch summaryPresentationAction {
            case .request:
                monitor.requestAgendaSummary(summaryRequest)
            case .cancel:
                monitor.cancelAgendaSummary()
            }
        }
        .task(id: isDropdownVisible) {
            guard isDropdownVisible else { return }
            await keepDropdownReferenceDateFresh()
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
        .onPreferenceChange(SplitSummaryPanelHeightPreferenceKey.self) { height in
            guard snapshot.shouldUseSplitDropdownLayout,
                  height > 0,
                  abs(splitSummaryPanelHeight - height) > 0.5 else {
                return
            }
            splitSummaryPanelHeight = height
        }
    }
}

private struct SplitSummaryPanelHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
