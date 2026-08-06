import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    enum SettingsPermissionKind: String, CaseIterable, Identifiable, Hashable {
        case events
        case reminders
        case location
        case contacts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .events:
                return "Calendar Events"
            case .reminders:
                return "Reminders"
            case .location:
                return "Location"
            case .contacts:
                return "Contacts"
            }
        }

        var summary: String {
            switch self {
            case .events:
                return "Read events and reveal football fixtures in Calendar."
            case .reminders:
                return "Load reminder due dates and completion status."
            case .location:
                return "Use automatic coordinates for sunrise, sunset, and daylight previews."
            case .contacts:
                return "Match organizers and invitees with Contacts to show names and photos in meeting previews."
            }
        }

        var fallbackSymbolName: String {
            switch self {
            case .events:
                return "calendar.badge.clock"
            case .reminders:
                return "checklist.checked"
            case .location:
                return "location.circle"
            case .contacts:
                return "person.crop.circle"
            }
        }

        var appIconPath: String {
            switch self {
            case .events:
                return "/System/Applications/Calendar.app"
            case .reminders:
                return "/System/Applications/Reminders.app"
            case .location:
                return "/System/Applications/Maps.app"
            case .contacts:
                return "/System/Applications/Contacts.app"
            }
        }

        var accentGradient: LinearGradient {
            switch self {
            case .events:
                return LinearGradient(
                    colors: [
                        Color(red: 0.24, green: 0.59, blue: 0.97),
                        Color(red: 0.30, green: 0.78, blue: 0.98),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .reminders:
                return LinearGradient(
                    colors: [
                        Color(red: 0.36, green: 0.77, blue: 0.35),
                        Color(red: 0.66, green: 0.87, blue: 0.34),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .location:
                return LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.52, blue: 0.27),
                        Color(red: 0.99, green: 0.76, blue: 0.31),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .contacts:
                return LinearGradient(
                    colors: [
                        Color(red: 0.43, green: 0.58, blue: 0.98),
                        Color(red: 0.42, green: 0.81, blue: 0.92),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }

        var privacySettingsDeepLink: String {
            switch self {
            case .events:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
            case .reminders:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
            case .location:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            case .contacts:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
            }
        }

        @MainActor private static let authorizationCacheInterval: TimeInterval = 30
        @MainActor private static var cachedEventAuthorizationStatus: EKAuthorizationStatus?
        @MainActor private static var cachedEventAuthorizationStatusDate: Date?
        @MainActor private static var cachedReminderAuthorizationStatus: EKAuthorizationStatus?
        @MainActor private static var cachedReminderAuthorizationStatusDate: Date?
        @MainActor private static let locationAuthorizationManager = CLLocationManager()
        @MainActor private static var cachedLocationAuthorizationStatus: CLAuthorizationStatus?
        @MainActor private static var cachedLocationAuthorizationStatusDate: Date?
        @MainActor private static var cachedContactsAuthorizationStatus: CNAuthorizationStatus?
        @MainActor private static var cachedContactsAuthorizationStatusDate: Date?

        @MainActor static func currentEventAuthorizationStatus(
            now: Date = Date(),
            forceRefresh: Bool = false
        ) -> EKAuthorizationStatus {
            if !forceRefresh,
               let cachedEventAuthorizationStatus,
               let cachedEventAuthorizationStatusDate,
               now.timeIntervalSince(cachedEventAuthorizationStatusDate) < authorizationCacheInterval {
                return cachedEventAuthorizationStatus
            }

            let status = EKEventStore.authorizationStatus(for: .event)
            cachedEventAuthorizationStatus = status
            cachedEventAuthorizationStatusDate = now
            return status
        }

        @MainActor static func currentReminderAuthorizationStatus(
            now: Date = Date(),
            forceRefresh: Bool = false
        ) -> EKAuthorizationStatus {
            if !forceRefresh,
               let cachedReminderAuthorizationStatus,
               let cachedReminderAuthorizationStatusDate,
               now.timeIntervalSince(cachedReminderAuthorizationStatusDate) < authorizationCacheInterval {
                return cachedReminderAuthorizationStatus
            }

            let status = EKEventStore.authorizationStatus(for: .reminder)
            cachedReminderAuthorizationStatus = status
            cachedReminderAuthorizationStatusDate = now
            return status
        }

        @MainActor static func currentLocationAuthorizationStatus(
            now: Date = Date(),
            forceRefresh: Bool = false
        ) -> CLAuthorizationStatus {
            if !forceRefresh,
               let cachedLocationAuthorizationStatus,
               let cachedLocationAuthorizationStatusDate,
               now.timeIntervalSince(cachedLocationAuthorizationStatusDate) < authorizationCacheInterval {
                return cachedLocationAuthorizationStatus
            }

            let status: CLAuthorizationStatus
            if CLLocationManager.locationServicesEnabled() {
                status = locationAuthorizationManager.authorizationStatus
            } else {
                status = .restricted
            }

            updateCachedLocationAuthorizationStatus(status, now: now)
            return status
        }

        @MainActor static func updateCachedLocationAuthorizationStatus(
            _ status: CLAuthorizationStatus,
            now: Date = Date()
        ) {
            cachedLocationAuthorizationStatus = status
            cachedLocationAuthorizationStatusDate = now
        }

        @MainActor static func currentContactsAuthorizationStatus(
            now: Date = Date(),
            forceRefresh: Bool = false
        ) -> CNAuthorizationStatus {
            if !forceRefresh,
               let cachedContactsAuthorizationStatus,
               let cachedContactsAuthorizationStatusDate,
               now.timeIntervalSince(cachedContactsAuthorizationStatusDate) < authorizationCacheInterval {
                return cachedContactsAuthorizationStatus
            }

            let status = CNContactStore.authorizationStatus(for: .contacts)
            updateCachedContactsAuthorizationStatus(status, now: now)
            return status
        }

        @MainActor static func updateCachedContactsAuthorizationStatus(
            _ status: CNAuthorizationStatus,
            now: Date = Date()
        ) {
            cachedContactsAuthorizationStatus = status
            cachedContactsAuthorizationStatusDate = now
        }
    }
}
