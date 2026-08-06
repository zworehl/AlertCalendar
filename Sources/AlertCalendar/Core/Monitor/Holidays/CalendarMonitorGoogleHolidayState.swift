import Foundation

struct CalendarMonitorGoogleHolidayState {
    var managedEventRecords: [ManagedGoogleHolidayEventRecord] = []
    var lastRefreshAttemptDate: Date?
}

extension CalendarMonitor {
    var managedGoogleHolidayEventRecords: [ManagedGoogleHolidayEventRecord] {
        get { googleHolidayState.managedEventRecords }
        set { googleHolidayState.managedEventRecords = newValue }
    }

    var lastGoogleHolidayRefreshAttemptDate: Date? {
        get { googleHolidayState.lastRefreshAttemptDate }
        set { googleHolidayState.lastRefreshAttemptDate = newValue }
    }
}
