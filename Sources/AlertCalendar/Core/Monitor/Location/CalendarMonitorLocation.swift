import CoreLocation
import CoreWLAN
import Foundation

extension CalendarMonitor {
    enum AutomaticAstronomyLocationRefreshTrigger {
        case manual
        case launch
        case hourly
        case appActivation
        case wifiNetworkChange

        fileprivate var minimumInterval: TimeInterval {
            switch self {
            case .hourly:
                return 60 * 60
            case .appActivation:
                // Avoid duplicating the launch refresh when the app becomes active immediately after startup.
                return 60
            case .manual, .launch, .wifiNetworkChange:
                return 0
            }
        }
    }

    private enum LocationRequestTimeout {
        static let authorizationSeconds: TimeInterval = 12
        static let oneShotCoordinateSeconds: TimeInterval = 25
        static let approximateNetworkSeconds: TimeInterval = 6
    }

    func refreshAstronomyCoordinatesFromSystem() {
        scheduleAutomaticAstronomyLocationRefresh(trigger: .manual)
    }

    func requestLocationPermissionIfNeeded() {
        guard CLLocationManager.locationServicesEnabled() else {
            astronomyLocationStatus = "Location Services are disabled."
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await requestLocationAuthorizationIfNeeded()
            switch status {
            case .authorizedAlways, .authorizedWhenInUse, .authorized:
                if defaults.bool(forKey: DefaultsKeys.useAutomaticAstronomyLocation) {
                    refreshAstronomyCoordinatesFromSystem()
                }
            case .denied, .restricted:
                astronomyLocationStatus = "Enable Location permission for automatic coordinates."
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    func refreshAutomaticAstronomyLocationIfNeeded(trigger: AutomaticAstronomyLocationRefreshTrigger) async {
        await refreshAutomaticAstronomyLocationIfNeeded(trigger: trigger, referenceDate: fixedSecondNow())
    }

    func scheduleHourlyAutomaticAstronomyLocationRefreshIfNeeded(now: Date) {
        scheduleAutomaticAstronomyLocationRefresh(trigger: .hourly, referenceDate: now)
    }

    func scheduleAutomaticAstronomyLocationRefresh(
        trigger: AutomaticAstronomyLocationRefreshTrigger,
        referenceDate: Date = AlertCalendarClock.nowRoundedToSecond()
    ) {
        guard automaticAstronomyLocationRefreshTask == nil else { return }

        automaticAstronomyLocationRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { automaticAstronomyLocationRefreshTask = nil }
            await refreshAutomaticAstronomyLocationIfNeeded(trigger: trigger, referenceDate: referenceDate)
        }
    }

    func startWiFiNetworkMonitoring() {
        guard wiFiClient == nil else { return }

        let client = CWWiFiClient.shared()
        let delegate = WiFiNetworkChangeDelegate { [weak self] interfaceName in
            Task { @MainActor [weak self] in
                self?.handleWiFiNetworkChange(interfaceName: interfaceName)
            }
        }

        client.delegate = delegate

        do {
            try client.startMonitoringEvent(with: .ssidDidChange)
            try client.startMonitoringEvent(with: .bssidDidChange)
            wiFiClient = client
            wiFiEventDelegate = delegate
            lastObservedWiFiNetworkIdentity = currentWiFiNetworkIdentity()
        } catch {
            wiFiClient = nil
            wiFiEventDelegate = nil
        }
    }

    func handleWiFiNetworkChange(interfaceName: String?) {
        let previousIdentity = lastObservedWiFiNetworkIdentity
        let currentIdentity = currentWiFiNetworkIdentity(preferredInterfaceName: interfaceName)
        lastObservedWiFiNetworkIdentity = currentIdentity

        guard let currentIdentity, currentIdentity != previousIdentity else { return }
        scheduleAutomaticAstronomyLocationRefresh(trigger: .wifiNetworkChange)
    }

    func currentWiFiNetworkIdentity(preferredInterfaceName: String? = nil) -> WiFiNetworkIdentity? {
        let client = wiFiClient ?? CWWiFiClient.shared()
        let interface: CWInterface?

        if let preferredInterfaceName, !preferredInterfaceName.isEmpty {
            interface = client.interface(withName: preferredInterfaceName) ?? client.interface()
        } else {
            interface = client.interface()
        }

        guard let interface else { return nil }
        let ssid = interface.ssid()
        let bssid = interface.bssid()
        guard ssid != nil || bssid != nil else { return nil }

        return WiFiNetworkIdentity(
            interfaceName: interface.interfaceName ?? preferredInterfaceName ?? "",
            ssid: ssid,
            bssid: bssid
        )
    }

    func refreshAutomaticAstronomyLocationIfNeeded(
        trigger: AutomaticAstronomyLocationRefreshTrigger,
        referenceDate: Date
    ) async {
        guard defaults.bool(forKey: DefaultsKeys.useAutomaticAstronomyLocation) else {
            astronomyLocationStatus = "Manual coordinates"
            return
        }

        guard Self.shouldRefreshAutomaticAstronomyLocation(
            lastAttemptDate: lastAutomaticAstronomyLocationRefreshAttemptDate,
            now: referenceDate,
            trigger: trigger
        ) else {
            return
        }

        guard !isAutomaticAstronomyLocationRefreshRunning else { return }

        lastAutomaticAstronomyLocationRefreshAttemptDate = referenceDate
        isAutomaticAstronomyLocationRefreshRunning = true
        defer { isAutomaticAstronomyLocationRefreshRunning = false }

        await updateAstronomyCoordinatesFromSystem()
    }

    nonisolated static func shouldRefreshAutomaticAstronomyLocation(
        lastAttemptDate: Date?,
        now: Date,
        trigger: AutomaticAstronomyLocationRefreshTrigger
    ) -> Bool {
        guard let lastAttemptDate else { return true }
        return now.timeIntervalSince(lastAttemptDate) >= trigger.minimumInterval
    }

    func requestLocationAuthorizationIfNeeded() async -> CLAuthorizationStatus {
        guard CLLocationManager.locationServicesEnabled() else {
            astronomyLocationStatus = "Location Services are disabled."
            return .restricted
        }

        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }

        astronomyLocationStatus = "Requesting location permissions..."

        return await withCheckedContinuation { continuation in
            var didResume = false
            let delegate = LocationPermissionDelegate { [weak self] status in
                guard status != .notDetermined else { return }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: status)
                self?.locationPermissionManager = nil
                self?.locationPermissionDelegate = nil
            }

            locationPermissionManager = manager
            locationPermissionDelegate = delegate
            manager.delegate = delegate
            manager.requestWhenInUseAuthorization()

            DispatchQueue.main.asyncAfter(deadline: .now() + LocationRequestTimeout.authorizationSeconds) { [weak self] in
                guard !didResume else { return }
                didResume = true
                let fallbackStatus = manager.authorizationStatus
                continuation.resume(returning: fallbackStatus)
                self?.locationPermissionManager = nil
                self?.locationPermissionDelegate = nil
            }
        }
    }

    func updateAstronomyCoordinatesFromSystem() async {
        guard defaults.bool(forKey: DefaultsKeys.useAutomaticAstronomyLocation) else {
            astronomyLocationStatus = "Manual coordinates"
            return
        }

        guard CLLocationManager.locationServicesEnabled() else {
            astronomyLocationStatus = "Location Services are disabled."
            return
        }

        let status = await requestLocationAuthorizationIfNeeded()

        guard isLocationAuthorized(status) else {
            astronomyLocationStatus = "Enable Location permission for automatic coordinates."
            return
        }

        guard let detectedLocation = await requestBestAvailableAstronomyLocation() else {
            astronomyLocationStatus = fallbackAstronomyLocationStatus(
                prefix: "Could not refresh current location"
            )
            return
        }

        let coordinate = detectedLocation.coordinate
        let roundedLatitude = AppSettingsRules.roundedCoordinate(coordinate.latitude)
        let roundedLongitude = AppSettingsRules.roundedCoordinate(coordinate.longitude)
        defaults.set(roundedLatitude, forKey: DefaultsKeys.astronomyLatitude)
        defaults.set(roundedLongitude, forKey: DefaultsKeys.astronomyLongitude)
        astronomyLocationStatus = String(
            format: "\(detectedLocation.statusPrefix): %.2f, %.2f",
            roundedLatitude,
            roundedLongitude
        )
        await refreshUpcomingItems()
    }

    func detectAstronomyCoordinate() async -> CLLocationCoordinate2D? {
        guard CLLocationManager.locationServicesEnabled() else {
            astronomyLocationStatus = "Location Services are disabled."
            return nil
        }

        let status = await requestLocationAuthorizationIfNeeded()

        guard isLocationAuthorized(status) else {
            astronomyLocationStatus = "Enable Location permission for automatic coordinates."
            return nil
        }

        guard let detectedLocation = await requestBestAvailableAstronomyLocation() else {
            astronomyLocationStatus = fallbackAstronomyLocationStatus(
                prefix: "Could not detect current location"
            )
            return nil
        }

        let coordinate = detectedLocation.coordinate
        astronomyLocationStatus = String(
            format: "\(detectedLocation.detectedStatusPrefix): %.2f, %.2f",
            AppSettingsRules.roundedCoordinate(coordinate.latitude),
            AppSettingsRules.roundedCoordinate(coordinate.longitude)
        )
        return coordinate
    }

    func requestBestAvailableAstronomyLocation() async -> AstronomyDetectedLocation? {
        if let coordinate = await requestOneShotCoordinate() {
            return AstronomyDetectedLocation(coordinate: coordinate, source: .system)
        }

        astronomyLocationStatus = "Core Location did not return coordinates. Trying approximate network location..."

        if let coordinate = await requestApproximateNetworkCoordinate() {
            return AstronomyDetectedLocation(coordinate: coordinate, source: .networkApproximate)
        }

        return nil
    }

    func requestOneShotCoordinate() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            let manager = CLLocationManager()
            var didResume = false
            let delegate = OneShotLocationDelegate { [weak self] coordinate in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: coordinate)
                self?.oneShotLocationManager = nil
                self?.oneShotLocationDelegate = nil
            }

            oneShotLocationManager = manager
            oneShotLocationDelegate = delegate
            manager.delegate = delegate
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.distanceFilter = kCLDistanceFilterNone
            astronomyLocationStatus = "Detecting location..."
            manager.requestLocation()
            manager.startUpdatingLocation()

            DispatchQueue.main.asyncAfter(deadline: .now() + LocationRequestTimeout.oneShotCoordinateSeconds) { [weak self] in
                guard !didResume else { return }
                didResume = true
                manager.stopUpdatingLocation()
                continuation.resume(returning: manager.location?.coordinate)
                self?.oneShotLocationManager = nil
                self?.oneShotLocationDelegate = nil
            }
        }
    }

    func requestApproximateNetworkCoordinate() async -> CLLocationCoordinate2D? {
        guard let url = URL(string: "https://ipapi.co/json/") else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = LocationRequestTimeout.approximateNetworkSeconds

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200 ... 299).contains(httpResponse.statusCode) {
                return nil
            }

            let decoded = try JSONDecoder().decode(ApproximateNetworkLocationResponse.self, from: data)
            guard let coordinate = decoded.coordinate else { return nil }
            return coordinate
        } catch {
            return nil
        }
    }

    func isLocationAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse, .authorized:
            return true
        default:
            return false
        }
    }

    func fallbackAstronomyLocationStatus(prefix: String) -> String {
        guard let latitude = defaults.object(forKey: DefaultsKeys.astronomyLatitude) as? Double,
              let longitude = defaults.object(forKey: DefaultsKeys.astronomyLongitude) as? Double else {
            return "\(prefix). Check Location Services and Wi-Fi, or enter coordinates manually."
        }

        guard (-90 ... 90).contains(latitude),
              (-180 ... 180).contains(longitude) else {
            return "\(prefix). Check Location Services and Wi-Fi, or enter coordinates manually."
        }

        return String(
            format: "\(prefix). Using saved coordinates: %.2f, %.2f",
            AppSettingsRules.roundedCoordinate(latitude),
            AppSettingsRules.roundedCoordinate(longitude)
        )
    }
}

struct AstronomyDetectedLocation {
    let coordinate: CLLocationCoordinate2D
    let source: AstronomyLocationSource

    var statusPrefix: String {
        switch source {
        case .system:
            return "Auto location"
        case .networkApproximate:
            return "Approximate auto location"
        }
    }

    var detectedStatusPrefix: String {
        switch source {
        case .system:
            return "Detected location"
        case .networkApproximate:
            return "Detected approximate location"
        }
    }
}

enum AstronomyLocationSource {
    case system
    case networkApproximate
}

private struct ApproximateNetworkLocationResponse: Decodable {
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude,
              let longitude,
              (-90 ... 90).contains(latitude),
              (-180 ... 180).contains(longitude) else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct WiFiNetworkIdentity: Equatable {
    let interfaceName: String
    let ssid: String?
    let bssid: String?
}

final class OneShotLocationDelegate: NSObject, CLLocationManagerDelegate {
    private var completion: ((CLLocationCoordinate2D?) -> Void)?
    private var resolved = false

    init(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.completion = completion
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations
            .filter { $0.horizontalAccuracy >= 0 }
            .min { $0.horizontalAccuracy < $1.horizontalAccuracy }
            ?? locations.last
        manager.stopUpdatingLocation()
        resolve(with: location?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let coordinate = manager.location?.coordinate {
            resolve(with: coordinate)
            return
        }

        if let locationError = error as? CLError,
           locationError.code == .locationUnknown {
            return
        }

        resolve(with: nil)
    }

    private func resolve(with coordinate: CLLocationCoordinate2D?) {
        guard !resolved else { return }
        resolved = true
        completion?(coordinate)
        completion = nil
    }
}

final class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    private let onChange: (CLAuthorizationStatus) -> Void

    init(onChange: @escaping (CLAuthorizationStatus) -> Void) {
        self.onChange = onChange
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onChange(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        onChange(status)
    }
}

final class WiFiNetworkChangeDelegate: NSObject, CWEventDelegate {
    private let onChange: (String?) -> Void

    init(onChange: @escaping (String?) -> Void) {
        self.onChange = onChange
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        onChange(interfaceName)
    }

    func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
        onChange(interfaceName)
    }

    func clientConnectionInterrupted() {
        onChange(nil)
    }

    func clientConnectionInvalidated() {
        onChange(nil)
    }
}
