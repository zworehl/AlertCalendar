import CoreLocation
import Foundation

extension CalendarMonitor {
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

            DispatchQueue.main.asyncAfter(deadline: .now() + CalendarMonitorLocationTimeout.authorizationSeconds) { [weak self] in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: manager.authorizationStatus)
                self?.locationPermissionManager = nil
                self?.locationPermissionDelegate = nil
            }
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
