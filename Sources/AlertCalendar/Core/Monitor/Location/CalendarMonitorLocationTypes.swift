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

        var minimumInterval: TimeInterval {
            switch self {
            case .hourly:
                return 60 * 60
            case .appActivation:
                return 15 * 60
            case .manual, .launch, .wifiNetworkChange:
                return 0
            }
        }
    }
}

enum CalendarMonitorLocationTimeout {
    static let authorizationSeconds: TimeInterval = 12
    static let oneShotCoordinateSeconds: TimeInterval = 25
    static let approximateNetworkSeconds: TimeInterval = 6
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

struct WiFiNetworkIdentity: Equatable {
    let interfaceName: String
    let ssid: String?
    let bssid: String?
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
