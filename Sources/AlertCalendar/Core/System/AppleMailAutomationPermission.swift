import AppKit
import ApplicationServices
import Foundation

enum AppleMailAutomationAuthorizationStatus: Equatable, Hashable, Sendable {
    case authorized
    case notDetermined
    case denied
    case mailUnavailable
}

@MainActor
enum AppleMailAutomationPermission {
    nonisolated private static let mailBundleIdentifier = "com.apple.mail"
    private static let service = AppleMailAutomationPermissionService(refreshInterval: 30, probe: probePermission)

    nonisolated private static func probePermission(_ asksForPermission: Bool) async throws -> AppleMailAutomationAuthorizationStatus {
        let response = try await AlertCalendarAutomation.shared.execute(
            .init(operation: .permission, bundleIdentifier: mailBundleIdentifier,
                  asksForPermission: asksForPermission),
            timeout: asksForPermission ? 120 : 3
        )
        return authorizationStatus(for: response.permissionStatus)
    }

    // This accessor never calls macOS. Refreshes are coalesced and bounded.
    static func currentStatus() -> AppleMailAutomationAuthorizationStatus {
        service.currentStatus()
    }

    static func refreshStatus(forceRefresh: Bool = false) async -> AppleMailAutomationAuthorizationStatus {
        await service.refresh(forceRefresh: forceRefresh)
    }

    static func requestAccess() async -> AppleMailAutomationAuthorizationStatus {
        let isRunning = await ensureMailIsRunning()
        guard isRunning else { return .mailUnavailable }
        return await service.requestAccess()
    }

    @MainActor
    private static func ensureMailIsRunning() async -> Bool {
        if !NSRunningApplication.runningApplications(
            withBundleIdentifier: mailBundleIdentifier
        ).isEmpty {
            return true
        }
        guard let mailURL = AlertCalendarWorkspace.applicationURL(
            forBundleIdentifier: mailBundleIdentifier
        ) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        return await withCheckedContinuation { continuation in
            AlertCalendarWorkspace.openApplication(
                at: mailURL,
                configuration: configuration
            ) { application, _ in
                continuation.resume(returning: application != nil)
            }
        }
    }

    nonisolated static func authorizationStatus(for status: Int32?) -> AppleMailAutomationAuthorizationStatus {
        switch status {
        case noErr:
            return .authorized
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .mailUnavailable
        }
    }
}

@MainActor
final class AppleMailAutomationPermissionService {
    typealias Probe = @Sendable (Bool) async throws -> AppleMailAutomationAuthorizationStatus
    private let probe: Probe
    private let refreshInterval: TimeInterval
    private var status: AppleMailAutomationAuthorizationStatus = .notDetermined
    private var lastRefresh: Date?
    private var inFlight: Task<AppleMailAutomationAuthorizationStatus, Never>?
    private var isRequestingAccess = false

    init(refreshInterval: TimeInterval = 30, probe: @escaping Probe) {
        self.refreshInterval = refreshInterval
        self.probe = probe
    }

    func currentStatus() -> AppleMailAutomationAuthorizationStatus {
        if needsRefresh { _ = start(asksForPermission: false) }
        return status
    }

    func refresh(forceRefresh: Bool = false) async -> AppleMailAutomationAuthorizationStatus {
        if let inFlight { return await inFlight.value }
        guard forceRefresh || needsRefresh else { return status }
        return await start(asksForPermission: false).value
    }

    func requestAccess() async -> AppleMailAutomationAuthorizationStatus {
        if let inFlight {
            let wasRequesting = isRequestingAccess
            let result = await inFlight.value
            if wasRequesting || result == .authorized { return result }
        }
        return await start(asksForPermission: true).value
    }

    private var needsRefresh: Bool {
        lastRefresh.map { Date().timeIntervalSince($0) >= refreshInterval } ?? true
    }

    private func start(asksForPermission: Bool) -> Task<AppleMailAutomationAuthorizationStatus, Never> {
        if let inFlight { return inFlight }
        isRequestingAccess = asksForPermission
        let probe = self.probe
        let task = Task { [weak self] in
            let result: AppleMailAutomationAuthorizationStatus
            do {
                result = try await probe(asksForPermission)
            } catch {
                result = .mailUnavailable
                CalendarMonitorLog.titleRewrite.error("Mail automation permission check failed: \(String(describing: error), privacy: .public)")
            }
            self?.status = result
            self?.lastRefresh = Date()
            self?.inFlight = nil
            self?.isRequestingAccess = false
            return result
        }
        inFlight = task
        return task
    }
}
