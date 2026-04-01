import SwiftUI

@main
struct AlertCalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = CalendarMonitor()

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(true)) {
            MenuContentView(kindFilter: nil, headerTitle: "Alert Calendar")
                .environmentObject(monitor)
        } label: {
            MenuBarStatusLabel(
                text: monitor.combinedMenuBarLabel,
                color: monitor.combinedMenuBarColor,
                alertedSegmentIndex: monitor.combinedMenuBarAlertedSegmentIndex,
                alertTextOpacity: monitor.combinedMenuBarAlertTextOpacity,
                dotColors: monitor.combinedMenuBarDotColors,
                markerStyles: monitor.combinedMenuBarMarkerStyles,
                segments: monitor.combinedMenuBarSegments,
                segmentBackgroundColors: monitor.combinedMenuBarSegmentBackgroundColors,
                segmentBackgroundProgresses: monitor.combinedMenuBarSegmentBackgroundProgresses,
                footballDisplay: monitor.combinedMenuBarFootballDisplay,
                footballTrailingText: monitor.combinedMenuBarFootballTrailingText,
                footballStatusText: monitor.combinedMenuBarFootballStatusText,
                footballStatusColor: monitor.combinedMenuBarFootballStatusColor,
                footballGoalHighlightSide: monitor.combinedMenuBarFootballGoalHighlightSide,
                footballGoalHighlightTextOpacity: monitor.combinedMenuBarFootballGoalHighlightTextOpacity
            )
        }
        .menuBarExtraStyle(.window)

        Window(WindowMetadata.preferencesTitle, id: WindowMetadata.preferencesID) {
            SettingsView(monitor: monitor)
        }
        .defaultSize(width: 1040, height: 820)
        .windowResizability(.automatic)
    }
}
