import AppKit
import ApplicationServices
import Foundation

enum AppleMailAutomationAuthorizationStatus: Equatable, Hashable, Sendable {
    case authorized
    case notDetermined
    case denied
    case mailUnavailable
}

enum AppleMailAutomationPermission {
    private static let mailBundleIdentifier = "com.apple.mail"

    static func currentStatus() -> AppleMailAutomationAuthorizationStatus {
        permissionStatus(askUserIfNeeded: false)
    }

    static func requestAccess() async -> AppleMailAutomationAuthorizationStatus {
        let isRunning = await ensureMailIsRunning()
        guard isRunning else { return .mailUnavailable }
        return await Task.detached(priority: .userInitiated) {
            permissionStatus(askUserIfNeeded: true)
        }.value
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

    private static func permissionStatus(
        askUserIfNeeded: Bool
    ) -> AppleMailAutomationAuthorizationStatus {
        var target = AEAddressDesc()
        let createStatus = mailBundleIdentifier.utf8CString.withUnsafeBytes { bytes in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                bytes.baseAddress,
                mailBundleIdentifier.utf8.count,
                &target
            )
        }
        guard createStatus == noErr else { return .mailUnavailable }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )
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
