import CoreWLAN
import Foundation

extension CalendarMonitor {
    func updateWiFiNetworkMonitoring(isEnabled: Bool) {
        if isEnabled {
            startWiFiNetworkMonitoring()
        } else {
            stopWiFiNetworkMonitoring()
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
            CalendarMonitorLog.location.debug("Wi-Fi monitoring failed: \(error.localizedDescription, privacy: .public)")
            wiFiClient = nil
            wiFiEventDelegate = nil
        }
    }

    func stopWiFiNetworkMonitoring() {
        guard let client = wiFiClient else { return }

        do {
            try client.stopMonitoringAllEvents()
        } catch {
            CalendarMonitorLog.location.debug("Stopping Wi-Fi monitoring failed: \(error.localizedDescription, privacy: .public)")
        }
        client.delegate = nil
        wiFiClient = nil
        wiFiEventDelegate = nil
        lastObservedWiFiNetworkIdentity = nil
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
}
