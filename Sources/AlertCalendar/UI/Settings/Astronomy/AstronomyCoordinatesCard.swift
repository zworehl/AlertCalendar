import AppKit
import SwiftUI

struct AstronomyCoordinatesCard: View {
    @Binding var useAutomaticAstronomyLocation: Bool
    @Binding var astronomyLatitude: Double
    @Binding var astronomyLongitude: Double
    let onDetectNow: () -> Void
    @State private var latitudeInput = ""
    @State private var longitudeInput = ""
    @FocusState private var focusedCoordinate: CoordinateAxis?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("Astronomy Coordinates")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 6) {
                        Toggle("Use automatic location", isOn: $useAutomaticAstronomyLocation)
                        InfoTipButton(text: "Uses your current location to fill latitude/longitude for sunrise, solar noon, sunset, and solar midnight calculation.")
                    }
                    Spacer(minLength: 8)
                    Button("Detect now") {
                        onDetectNow()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Toggle("Use automatic location", isOn: $useAutomaticAstronomyLocation)
                        InfoTipButton(text: "Uses your current location to fill latitude/longitude for sunrise, solar noon, sunset, and solar midnight calculation.")
                    }
                    Button("Detect now") {
                        onDetectNow()
                    }
                }
            }

            if !useAutomaticAstronomyLocation {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        coordinateField(
                            title: "Latitude",
                            text: $latitudeInput,
                            axis: .latitude
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        coordinateField(
                            title: "Longitude",
                            text: $longitudeInput,
                            axis: .longitude
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 10) {
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func coordinateField(title: String, text: Binding<String>, axis: CoordinateAxis) -> some View {
        let liveTextBinding = Binding<String>(
            get: { text.wrappedValue },
            set: { newValue in
                text.wrappedValue = newValue
                if let parsed = parsedCoordinateValue(newValue, axis: axis) {
                    switch axis {
                    case .latitude:
                        astronomyLatitude = parsed
                    case .longitude:
                        astronomyLongitude = parsed
                    }
                }
            }
        )

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text(title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                TextField(
                    title,
                    text: liveTextBinding
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
                .frame(width: 66)
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .foregroundStyle(.secondary)
                TextField(
                    title,
                    text: liveTextBinding
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
                .frame(width: 66, alignment: .leading)
            }
            .fixedSize(horizontal: true, vertical: false)
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

    private enum CoordinateAxis: Hashable {
        case latitude
        case longitude
    }

    private func parsedCoordinateValue(_ raw: String, axis: CoordinateAxis) -> Double? {
        guard let normalized = normalizeCoordinateString(raw),
              let parsed = Double(normalized) else {
            return nil
        }

        let rounded = roundedCoordinate(parsed)
        switch axis {
        case .latitude:
            return max(-90, min(90, rounded))
        case .longitude:
            return max(-180, min(180, rounded))
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

    private func roundedCoordinate(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func formattedCoordinate(_ value: Double) -> String {
        String(format: "%.2f", roundedCoordinate(value))
    }
}
