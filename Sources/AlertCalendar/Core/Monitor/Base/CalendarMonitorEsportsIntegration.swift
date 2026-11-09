import Foundation

extension CalendarMonitor {
    func configureEsportsRuntime() {
        let settings = snapshotSettings()
        esportsRuntime.configure(
            settings: settings.esports,
            selectedCalendarIDs: focusVisibleCalendarIDs(for: .event, baseIDs: settings.selectedEventCalendarIDs),
            hasEventsAccess: hasEventsAccess
        )
    }

    func refreshEsports(force: Bool) async {
        guard startsBackgroundServices else { return }
        configureEsportsRuntime()
        await esportsRuntime.refresh(force: force)
    }
}
