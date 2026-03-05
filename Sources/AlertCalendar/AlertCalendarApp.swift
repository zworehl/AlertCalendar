import SwiftUI

@main
struct AlertCalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = CalendarMonitor()

    var body: some Scene {
        MenuBarExtra {
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
                segmentBackgroundProgresses: monitor.combinedMenuBarSegmentBackgroundProgresses
            )
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "preferences") {
            SettingsView(monitor: monitor)
        }
        .windowResizability(.contentSize)
    }
}
