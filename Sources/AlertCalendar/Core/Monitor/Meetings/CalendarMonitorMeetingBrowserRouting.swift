import Foundation

extension CalendarMonitor {
    func openMeeting(_ item: UpcomingItem) {
        guard let meetingURL = item.meetingURL else { return }

        let route = MeetingBrowserRouting.route(
            for: item.calendarID,
            settings: currentSettings.meetingBrowserRouting
        )
        Task.detached(priority: .userInitiated) {
            await MeetingBrowserLauncher.open(meetingURL, route: route)
        }
    }
}
