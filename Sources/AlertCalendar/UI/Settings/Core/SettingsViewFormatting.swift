import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    nonisolated static func durationValueText(value: Int, singular: String, plural: String) -> String {
        let normalizedValue = max(0, value)
        let unit = normalizedValue == 1 ? singular : plural
        return "\(normalizedValue) \(unit)"
    }

    nonisolated static func menuBarRotationWindowValueText(minutes: Int) -> String {
        let normalizedMinutes = max(1, minutes)
        if normalizedMinutes < 60 {
            return durationValueText(
                value: normalizedMinutes,
                singular: "minute",
                plural: "minutes"
            )
        }

        let hours = normalizedMinutes / 60
        let remainingMinutes = normalizedMinutes % 60

        if remainingMinutes == 0 {
            return durationValueText(
                value: hours,
                singular: "hour",
                plural: "hours"
            )
        }

        return "\(durationValueText(value: hours, singular: "hour", plural: "hours")) \(durationValueText(value: remainingMinutes, singular: "minute", plural: "minutes"))"
    }

    static func isGrantedEventKitAuthorizationStatus(_ status: EKAuthorizationStatus) -> Bool {
        if status == .authorized {
            return true
        }

        if #available(macOS 14.0, *) {
            if status == .fullAccess {
                return true
            }

            if status == .writeOnly {
                return false
            }
        }

        if status == .notDetermined || status == .denied || status == .restricted {
            return false
        }

        return false
    }

    static func permissionGrantState(for status: EKAuthorizationStatus) -> PermissionGrantState {
        if status == .authorized {
            return .allowed
        }

        if #available(macOS 14.0, *) {
            if status == .fullAccess {
                return .allowed
            }

            if status == .writeOnly {
                return .limited
            }
        }

        if status == .notDetermined {
            return .notRequested
        }

        if status == .denied {
            return .denied
        }

        if status == .restricted {
            return .restricted
        }

        return .restricted
    }

    static func permissionGrantState(for status: CLAuthorizationStatus) -> PermissionGrantState {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse, .authorized:
            return .allowed
        case .notDetermined:
            return .notRequested
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    static func permissionGrantState(for status: CNAuthorizationStatus) -> PermissionGrantState {
        switch status {
        case .authorized:
            return .allowed
        case .notDetermined:
            return .notRequested
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }
}
