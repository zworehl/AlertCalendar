import EventKit
import Foundation

enum EventTravelTimeResolver {
    static func travelTime(for event: EKEvent) -> TimeInterval {
        if let raw = (event as NSObject).value(forKey: "travelTime") as? NSNumber {
            return max(0, raw.doubleValue)
        }
        if let raw = (event as NSObject).value(forKey: "travelTime") as? Double {
            return max(0, raw)
        }
        return 0
    }

    static func travelTimeMinutes(for event: EKEvent) -> Int? {
        let seconds = travelTime(for: event)
        guard seconds >= 60 else { return nil }
        return max(1, Int(ceil(seconds / 60.0)))
    }

    static func resetTravelTime(on event: EKEvent) {
        (event as NSObject).setValue(0, forKey: "travelTime")
    }
}
