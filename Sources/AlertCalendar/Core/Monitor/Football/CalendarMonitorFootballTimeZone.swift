import EventKit
import Foundation

extension CalendarMonitor {
    func applyFootballTimeZone(to event: EKEvent, locationText: String?) async {
        guard let locationText = normalizedLocation(for: locationText) else {
            event.timeZone = nil
            return
        }

        if let timeZone = await footballTimeZone(for: locationText) {
            event.timeZone = timeZone
        }
    }

    func footballTimeZoneNeedsUpdate(for event: EKEvent, locationText: String?) async -> Bool {
        guard let locationText = normalizedLocation(for: locationText) else {
            return event.timeZone != nil
        }

        let desiredTimeZone = await footballTimeZone(for: locationText)
        guard let desiredTimeZone else { return false }

        return Self.footballEventTimeZoneNeedsUpdate(
            currentTimeZone: event.timeZone,
            desiredTimeZone: desiredTimeZone
        )
    }

    func footballTimeZone(for locationText: String?) async -> TimeZone? {
        guard let locationText = normalizedLocation(for: locationText) else { return nil }
        return await LocationCoordinateResolver.shared.timeZone(for: locationText)
    }

    nonisolated static func footballEventTimeZoneNeedsUpdate(
        currentTimeZone: TimeZone?,
        desiredTimeZone: TimeZone?
    ) -> Bool {
        normalizedFootballTimeZoneIdentifier(currentTimeZone) != normalizedFootballTimeZoneIdentifier(desiredTimeZone)
    }

    nonisolated static func normalizedFootballTimeZoneIdentifier(_ timeZone: TimeZone?) -> String? {
        guard let identifier = timeZone?.identifier.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty else {
            return nil
        }

        return TimeZone(identifier: identifier)?.identifier ?? identifier
    }
}
