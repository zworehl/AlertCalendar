import AppKit
import SwiftUI

struct DaylightSolarState {
    let declination: Double
    let subsolarLongitude: Double

    init(date: Date) {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let dayOfYear = Double(utcCalendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let components = utcCalendar.dateComponents([.hour, .minute, .second], from: date)
        let utcHours = Double(components.hour ?? 0)
            + (Double(components.minute ?? 0) / 60.0)
            + (Double(components.second ?? 0) / 3600.0)

        declination = 23.44 * sin((2.0 * .pi / 365.0) * (dayOfYear - 81.0))
        let longitude = 180.0 - (utcHours * 15.0)
        subsolarLongitude = DaylightSolarState.normalizedLongitude(longitude)
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var value = longitude.truncatingRemainder(dividingBy: 360.0)
        if value > 180.0 {
            value -= 360.0
        } else if value < -180.0 {
            value += 360.0
        }
        return value
    }
}

func highlightPill(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
        Text(subtitle)
            .font(.caption.weight(.semibold))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.regularMaterial, in: Capsule())
}
