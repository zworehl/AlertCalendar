import Foundation
import Network

/// Reachability is a retry signal, never evidence that a feed has recovered.
struct NetworkRecoveryState {
    private var wasAvailable: Bool?

    mutating func observe(isAvailable: Bool) -> Bool {
        defer { wasAvailable = isAvailable }
        return wasAvailable == false && isAvailable
    }
}

@MainActor
final class NetworkRecoveryObserver {
    private let monitor = NWPathMonitor()
    private var state = NetworkRecoveryState()
    private let onRecovery: @MainActor @Sendable () -> Void

    init(onRecovery: @escaping @MainActor @Sendable () -> Void) {
        self.onRecovery = onRecovery
        monitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, state.observe(isAvailable: isAvailable) else { return }
                onRecovery()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.zworehl.alertcalendar.network-recovery"))
    }

    deinit { monitor.cancel() }
}
