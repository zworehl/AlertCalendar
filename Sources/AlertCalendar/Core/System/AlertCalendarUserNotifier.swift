import Foundation
import UserNotifications

enum AlertCalendarUserNotifier {
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        await ensureAuthorization()
    }

    static func deliver(identifier: String, title: String, body: String) async {
        guard await ensureAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        try? await add(request)
    }

    private static func ensureAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let authorizationStatus = await notificationAuthorizationStatus(for: center)

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await requestAuthorization(for: center)) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func notificationAuthorizationStatus(
        for center: UNUserNotificationCenter
    ) async -> UNAuthorizationStatus {
        let rawValue = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus.rawValue)
            }
        }
        return UNAuthorizationStatus(rawValue: rawValue) ?? .denied
    }

    private static func requestAuthorization(
        for center: UNUserNotificationCenter
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: granted)
            }
        }
    }

    private static func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
        }
    }
}
