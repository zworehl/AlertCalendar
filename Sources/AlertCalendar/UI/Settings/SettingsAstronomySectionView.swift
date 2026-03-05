import AppKit
import SwiftUI

struct SettingsAstronomySectionView: View {
    typealias SolarMoments = (sunrise: Date?, solarNoon: Date?, sunset: Date?, solarMidnight: Date?)

    @Binding var useAutomaticAstronomyLocation: Bool
    @Binding var astronomyLatitude: Double
    @Binding var astronomyLongitude: Double
    let astronomyLocationStatus: String
    let onDetectNow: () -> Void
    let solarTimesProvider: (Date, (lat: Double, lon: Double), TimeZone) -> SolarMoments?
    @State private var latitudeInput = ""
    @State private var longitudeInput = ""
    @FocusState private var focusedCoordinate: CoordinateAxis?

    var body: some View {
        GroupBox("Astronomy (Sun Path)") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    coordinatesSection
                        .frame(maxWidth: .infinity, alignment: .leading)
                    astronomyTimesSection
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 10) {
                    coordinatesSection
                    astronomyTimesSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            latitudeInput = formattedCoordinate(astronomyLatitude)
            longitudeInput = formattedCoordinate(astronomyLongitude)
        }
        .onChange(of: astronomyLatitude) { value in
            guard focusedCoordinate != .latitude else { return }
            latitudeInput = formattedCoordinate(value)
        }
        .onChange(of: astronomyLongitude) { value in
            guard focusedCoordinate != .longitude else { return }
            longitudeInput = formattedCoordinate(value)
        }
    }

    private var coordinatesSection: some View {
        GroupBox("Coordinates") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Toggle("Use automatic location", isOn: $useAutomaticAstronomyLocation)
                        InfoTipButton(text: "Uses your current location to fill latitude/longitude for sunrise, solar noon, sunset, and solar midnight calculation.")
                    }
                    Spacer()
                    Button("Detect now") {
                        onDetectNow()
                    }
                }

                Text(astronomyLocationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        coordinateField(
                            title: "Latitude",
                            text: $latitudeInput,
                            axis: .latitude
                        )
                        coordinateField(
                            title: "Longitude",
                            text: $longitudeInput,
                            axis: .longitude
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        coordinateField(
                            title: "Latitude",
                            text: $latitudeInput,
                            axis: .latitude
                        )
                        coordinateField(
                            title: "Longitude",
                            text: $longitudeInput,
                            axis: .longitude
                        )
                    }
                }
                .disabled(useAutomaticAstronomyLocation)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var astronomyTimesSection: some View {
        GroupBox("Calculated Times") {
            VStack(alignment: .leading, spacing: 8) {
                if let preview = nextAstronomyTimes() {
                    astronomyMomentsLayout(preview: preview)
                } else {
                    Text("Enter valid coordinates to calculate astronomy moments.")
                        .foregroundStyle(.secondary)
                }

                Text("Sunrise, solar noon, sunset, and solar midnight are calculated locally from these coordinates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func astronomyMomentsLayout(preview: SolarMoments) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    astronomyTimeItem(moment: .sunrise, value: formattedAstronomyMoment(preview.sunrise))
                    astronomyTimeItem(moment: .solarNoon, value: formattedAstronomyMoment(preview.solarNoon))
                }
                VStack(alignment: .leading, spacing: 8) {
                    astronomyTimeItem(moment: .sunset, value: formattedAstronomyMoment(preview.sunset))
                    astronomyTimeItem(moment: .solarMidnight, value: formattedAstronomyMoment(preview.solarMidnight))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                astronomyTimeItem(moment: .sunrise, value: formattedAstronomyMoment(preview.sunrise))
                astronomyTimeItem(moment: .solarNoon, value: formattedAstronomyMoment(preview.solarNoon))
                astronomyTimeItem(moment: .sunset, value: formattedAstronomyMoment(preview.sunset))
                astronomyTimeItem(moment: .solarMidnight, value: formattedAstronomyMoment(preview.solarMidnight))
            }
        }
    }

    private func astronomyTimeItem(moment: AstronomyMoment, value: String) -> some View {
        HStack(spacing: 8) {
            astronomyIcon(moment: moment)
            VStack(alignment: .leading, spacing: 0) {
                Text(moment.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func astronomyIcon(moment: AstronomyMoment) -> some View {
        if let image = AstronomyIconProvider.image(for: moment, pointSize: 14) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
        } else {
            Circle()
                .fill(.secondary)
                .frame(width: 8, height: 8)
        }
    }

    private func coordinateField(title: String, text: Binding<String>, axis: CoordinateAxis) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                title,
                text: text
            )
            .focused($focusedCoordinate, equals: axis)
            .onChange(of: focusedCoordinate) { focused in
                if focused != axis {
                    commitCoordinateText(axis: axis)
                }
            }
            .onSubmit {
                commitCoordinateText(axis: axis)
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)
        }
    }

    private func roundedTo3Decimals(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private enum CoordinateAxis: Hashable {
        case latitude
        case longitude
    }

    private func parsedCoordinateValue(_ raw: String, axis: CoordinateAxis) -> Double? {
        guard let normalized = normalizeCoordinateString(raw),
              let parsed = Double(normalized) else {
            return nil
        }

        let rounded = roundedTo3Decimals(parsed)
        switch axis {
        case .latitude:
            return max(-90, min(90, rounded))
        case .longitude:
            return max(-180, min(180, rounded))
        }
    }

    private func commitCoordinateText(axis: CoordinateAxis) {
        switch axis {
        case .latitude:
            if let parsed = parsedCoordinateValue(latitudeInput, axis: .latitude) {
                astronomyLatitude = parsed
            }
            latitudeInput = formattedCoordinate(astronomyLatitude)
        case .longitude:
            if let parsed = parsedCoordinateValue(longitudeInput, axis: .longitude) {
                astronomyLongitude = parsed
            }
            longitudeInput = formattedCoordinate(astronomyLongitude)
        }
    }

    private func normalizeCoordinateString(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lastDot = trimmed.lastIndex(of: ".")
        let lastComma = trimmed.lastIndex(of: ",")

        if lastDot != nil || lastComma != nil {
            let decimalSeparator: Character = {
                if let dot = lastDot, let comma = lastComma {
                    return dot > comma ? "." : ","
                }
                return lastDot != nil ? "." : ","
            }()

            let chars = trimmed.filter { $0.isNumber || $0 == "-" || $0 == "." || $0 == "," }
            let unified: String
            if decimalSeparator == "." {
                unified = chars.replacingOccurrences(of: ",", with: "")
            } else {
                unified = chars.replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            }
            return unified
        }

        return trimmed
    }

    private func formattedCoordinate(_ value: Double) -> String {
        String(format: "%.3f", roundedTo3Decimals(value))
    }

    private func nextAstronomyTimes() -> SolarMoments? {
        guard (-90 ... 90).contains(astronomyLatitude),
              (-180 ... 180).contains(astronomyLongitude) else {
            return nil
        }

        let now = Date()
        let coordinate = (lat: astronomyLatitude, lon: astronomyLongitude)
        let calendar = Calendar.current
        var nextSunrise: Date?
        var nextSolarNoon: Date?
        var nextSunset: Date?
        var nextSolarMidnight: Date?

        for offset in 0 ... 5 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let times = solarTimesProvider(day, coordinate, .current) else {
                continue
            }

            if nextSunrise == nil, let sunrise = times.sunrise, sunrise > now {
                nextSunrise = sunrise
            }
            if nextSolarNoon == nil, let solarNoon = times.solarNoon, solarNoon > now {
                nextSolarNoon = solarNoon
            }
            if nextSunset == nil, let sunset = times.sunset, sunset > now {
                nextSunset = sunset
            }
            if nextSolarMidnight == nil, let solarMidnight = times.solarMidnight, solarMidnight > now {
                nextSolarMidnight = solarMidnight
            }

            if nextSunrise != nil, nextSolarNoon != nil, nextSunset != nil, nextSolarMidnight != nil {
                break
            }
        }

        return (nextSunrise, nextSolarNoon, nextSunset, nextSolarMidnight)
    }

    private func formattedAstronomyMoment(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        let calendar = Calendar.current
        let prefix: String
        if calendar.isDateInToday(date) {
            prefix = "Today"
        } else if calendar.isDateInTomorrow(date) {
            prefix = "Tomorrow"
        } else {
            prefix = Self.dayFormatter.string(from: date)
        }
        return "\(prefix), \(Self.timeFormatter.string(from: date))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
