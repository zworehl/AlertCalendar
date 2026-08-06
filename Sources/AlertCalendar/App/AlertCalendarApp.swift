import SwiftUI

@main
struct AlertCalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitorOwner = CalendarMonitorOwner()

    private var monitor: CalendarMonitor {
        monitorOwner.monitor
    }

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    private func resolvedSettingsWindow() -> NSWindow? {
        let settingsIdentifier = NSUserInterfaceItemIdentifier(WindowMetadata.preferencesID)
        let candidateWindows: [NSWindow?] = [NSApp.keyWindow, NSApp.mainWindow]

        for candidate in candidateWindows {
            guard let window = candidate else { continue }
            if window.identifier == settingsIdentifier || window.title == WindowMetadata.preferencesTitle {
                return window
            }
        }

        return NSApp.windows.first { window in
            window.identifier == settingsIdentifier || window.title == WindowMetadata.preferencesTitle
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(true)) {
            MenuContentView(kindFilter: nil, headerTitle: "Alert Calendar")
                .environmentObject(monitor)
        } label: {
            MenuBarMonitorStatusLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Window(WindowMetadata.preferencesTitle, id: WindowMetadata.preferencesID) {
            SettingsView(monitor: monitor)
        }
        .defaultSize(width: 1040, height: 820)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Full Screen") {
                    resolvedSettingsWindow()?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }
    }
}

@MainActor
private final class CalendarMonitorOwner: ObservableObject {
    let monitor = CalendarMonitor()
}

private struct MenuBarMonitorStatusLabel: View {
    @ObservedObject var monitor: CalendarMonitor

    @ViewBuilder
    var body: some View {
        if monitor.isInitialLoadInProgress {
            MenuBarLoadingIndicator()
        } else {
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
                segmentParticipationStatuses: monitor.combinedMenuBarSegmentParticipationStatuses,
                segmentTextureStatuses: monitor.combinedMenuBarSegmentTextureStatuses,
                segmentAccessorySymbolNames: monitor.combinedMenuBarSegmentAccessorySymbolNames,
                footballDisplay: monitor.combinedMenuBarFootballDisplay,
                footballTrailingText: monitor.combinedMenuBarFootballTrailingText,
                footballStatusText: monitor.combinedMenuBarFootballStatusText,
                footballStatusColor: monitor.combinedMenuBarFootballStatusColor,
                footballGoalHighlightSide: monitor.combinedMenuBarFootballGoalHighlightSide,
                footballGoalHighlightTextOpacity: monitor.combinedMenuBarFootballGoalHighlightTextOpacity
            )
        }
    }
}
