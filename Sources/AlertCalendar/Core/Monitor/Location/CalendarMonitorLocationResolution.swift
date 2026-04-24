import CoreLocation
import Foundation

extension CalendarMonitor {
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

            DispatchQueue.main.asyncAfter(deadline: .now() + CalendarMonitorLocationTimeout.oneShotCoordinateSeconds) { [weak self] in
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
        request.timeoutInterval = CalendarMonitorLocationTimeout.approximateNetworkSeconds

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200 ... 299).contains(httpResponse.statusCode) {
                return nil
            }

            let decoded = try JSONDecoder().decode(ApproximateNetworkLocationResponse.self, from: data)
            return decoded.coordinate
        } catch {
            CalendarMonitorLog.location.debug("Approximate network location failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
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
