import CoreLocation
import CoreWLAN
import Foundation

struct CalendarMonitorLocationRuntimeState {
    var oneShotLocationManager: CLLocationManager?
    var oneShotLocationDelegate: OneShotLocationDelegate?
    var permissionManager: CLLocationManager?
    var permissionDelegate: LocationPermissionDelegate?
    var automaticAstronomyRefreshTask: Task<Void, Never>?
    var isAutomaticAstronomyRefreshRunning = false
    var lastAutomaticAstronomyRefreshAttemptDate: Date?
    var wiFiClient: CWWiFiClient?
    var wiFiEventDelegate: WiFiNetworkChangeDelegate?
    var lastObservedWiFiNetworkIdentity: WiFiNetworkIdentity?
}

extension CalendarMonitor {
    var oneShotLocationManager: CLLocationManager? {
        get { locationRuntimeState.oneShotLocationManager }
        set { locationRuntimeState.oneShotLocationManager = newValue }
    }

    var oneShotLocationDelegate: OneShotLocationDelegate? {
        get { locationRuntimeState.oneShotLocationDelegate }
        set { locationRuntimeState.oneShotLocationDelegate = newValue }
    }

    var locationPermissionManager: CLLocationManager? {
        get { locationRuntimeState.permissionManager }
        set { locationRuntimeState.permissionManager = newValue }
    }

    var locationPermissionDelegate: LocationPermissionDelegate? {
        get { locationRuntimeState.permissionDelegate }
        set { locationRuntimeState.permissionDelegate = newValue }
    }

    var automaticAstronomyLocationRefreshTask: Task<Void, Never>? {
        get { locationRuntimeState.automaticAstronomyRefreshTask }
        set { locationRuntimeState.automaticAstronomyRefreshTask = newValue }
    }

    var isAutomaticAstronomyLocationRefreshRunning: Bool {
        get { locationRuntimeState.isAutomaticAstronomyRefreshRunning }
        set { locationRuntimeState.isAutomaticAstronomyRefreshRunning = newValue }
    }

    var lastAutomaticAstronomyLocationRefreshAttemptDate: Date? {
        get { locationRuntimeState.lastAutomaticAstronomyRefreshAttemptDate }
        set { locationRuntimeState.lastAutomaticAstronomyRefreshAttemptDate = newValue }
    }

    var wiFiClient: CWWiFiClient? {
        get { locationRuntimeState.wiFiClient }
        set { locationRuntimeState.wiFiClient = newValue }
    }

    var wiFiEventDelegate: WiFiNetworkChangeDelegate? {
        get { locationRuntimeState.wiFiEventDelegate }
        set { locationRuntimeState.wiFiEventDelegate = newValue }
    }

    var lastObservedWiFiNetworkIdentity: WiFiNetworkIdentity? {
        get { locationRuntimeState.lastObservedWiFiNetworkIdentity }
        set { locationRuntimeState.lastObservedWiFiNetworkIdentity = newValue }
    }
}
