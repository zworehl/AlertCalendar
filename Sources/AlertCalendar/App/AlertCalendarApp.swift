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
                .environment(\.locale, AlertCalendarLanguage.english)
        } label: {
            MenuBarMonitorStatusLabel(presentation: monitor.menuBarPresentationModel)
        }
        .menuBarExtraStyle(.window)

        Window(WindowMetadata.preferencesTitle, id: WindowMetadata.preferencesID) {
            SettingsView(monitor: monitor)
                .environment(\.locale, AlertCalendarLanguage.english)
        }
        .defaultSize(width: 1240, height: 840)
        .windowResizability(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
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
    @ObservedObject var presentation: MenuBarPresentationModel
    @Environment(\.openWindow) private var openWindow

    @ViewBuilder
    var body: some View {
        Group {
            if presentation.isInitialLoading {
                MenuBarLoadingIndicator()
            } else {
                let state = presentation.state
                MenuBarStatusLabel(
                    text: state.label,
                    color: state.color,
                    alertedSegmentIndex: state.alertedSegmentIndex,
                    alertTextOpacity: state.alertTextOpacity,
                    dotColors: state.dotColors,
                    markerStyles: state.markerStyles,
                    segments: state.segments,
                    segmentBackgroundColors: state.segmentBackgroundColors,
                    segmentBackgroundProgresses: state.segmentBackgroundProgresses,
                    segmentParticipationStatuses: state.segmentParticipationStatuses,
                    segmentTextureStatuses: state.segmentTextureStatuses,
                    segmentAccessorySymbolNames: state.segmentAccessorySymbolNames,
                    footballDisplay: state.footballDisplay,
                    footballTrailingText: state.footballTrailingText,
                    footballStatusText: state.footballStatusText,
                    footballStatusColor: state.footballStatusColor,
                    footballGoalHighlightSide: state.footballGoalHighlightSide,
                    footballGoalHighlightTextOpacity: state.footballGoalHighlightTextOpacity
                )
                .help(state.fullTitleText ?? state.label)
                .accessibilityLabel(state.fullTitleText ?? state.label)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .alertCalendarOpenSettingsRequested)) { _ in
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.prepareForSettingsPresentation()
            }
            openWindow(id: WindowMetadata.preferencesID)
        }
    }
}
