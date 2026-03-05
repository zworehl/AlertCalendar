import CoreLocation
import Foundation

extension CalendarMonitor {
    private enum LocationRequestTimeout {
        static let authorizationSeconds: TimeInterval = 12
        static let oneShotCoordinateSeconds: TimeInterval = 15
    }

    func refreshAstronomyCoordinatesFromSystem() {
        Task { await updateAstronomyCoordinatesFromSystem() }
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

        guard let coordinate = await requestOneShotCoordinate() else {
            astronomyLocationStatus = "Could not determine current location."
            return
        }

        defaults.set(coordinate.latitude, forKey: DefaultsKeys.astronomyLatitude)
        defaults.set(coordinate.longitude, forKey: DefaultsKeys.astronomyLongitude)
        astronomyLocationStatus = String(
            format: "Auto location: %.4f, %.4f",
            coordinate.latitude,
            coordinate.longitude
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

        guard let coordinate = await requestOneShotCoordinate() else {
            astronomyLocationStatus = "Could not determine current location."
            return nil
        }

        astronomyLocationStatus = String(
            format: "Detected location: %.3f, %.3f",
            coordinate.latitude,
            coordinate.longitude
        )
        return coordinate
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
            manager.requestLocation()

            DispatchQueue.main.asyncAfter(deadline: .now() + LocationRequestTimeout.oneShotCoordinateSeconds) { [weak self] in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: nil)
                self?.oneShotLocationManager = nil
                self?.oneShotLocationDelegate = nil
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

final class OneShotLocationDelegate: NSObject, CLLocationManagerDelegate {
    private var completion: ((CLLocationCoordinate2D?) -> Void)?
    private var resolved = false

    init(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.completion = completion
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        resolve(with: locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
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
