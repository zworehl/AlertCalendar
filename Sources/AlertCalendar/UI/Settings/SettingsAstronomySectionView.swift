import AppKit
import SwiftUI

struct AstronomyCoordinatesCard: View {
    @Binding var useAutomaticAstronomyLocation: Bool
    @Binding var astronomyLatitude: Double
    @Binding var astronomyLongitude: Double
    let astronomyLocationStatus: String
    let onDetectNow: () -> Void
    @State private var latitudeInput = ""
    @State private var longitudeInput = ""
    @FocusState private var focusedCoordinate: CoordinateAxis?

    var body: some View {
        GroupBox("Coordinates") {
            VStack(alignment: .leading, spacing: 10) {
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

                Text(astronomyLocationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                .disabled(useAutomaticAstronomyLocation)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                .frame(minWidth: 110, maxWidth: 150)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
            }
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

        let rounded = roundedTo3Decimals(parsed)
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

    private func roundedTo3Decimals(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private func formattedCoordinate(_ value: Double) -> String {
        String(format: "%.3f", roundedTo3Decimals(value))
    }
}

struct SettingsAstronomySectionView: View {
    typealias SolarMoments = (sunrise: Date?, solarNoon: Date?, sunset: Date?, solarMidnight: Date?)
    typealias AstronomyPreviewMoment = (moment: AstronomyMoment, date: Date)

    let title: String
    let showsCalculatedTimes: Bool
    let showsSunriseSunset: Bool
    let showsSolarNoonMidnight: Bool
    let showsMoonPhases: Bool
    let showsOrbitalHighlights: Bool
    let astronomyLatitude: Double
    let astronomyLongitude: Double
    let solarTimesProvider: (Date, (lat: Double, lon: Double), TimeZone) -> SolarMoments?
    let nextLunarPhasesProvider: (Date) -> [AstronomyPreviewMoment]
    let nextOrbitalHighlightsProvider: (Date) -> [AstronomyPreviewMoment]

    var body: some View {
        GroupBox(title) {
            if showsCalculatedTimes {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            astronomyTimesSection
                                .frame(maxWidth: .infinity, alignment: .leading)
                            orbitalHighlightsSection
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            astronomyTimesSection
                            orbitalHighlightsSection
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    lunarPhasesSection
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enable astronomy feeds to preview sunrise, moon phases, and orbital highlights here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var astronomyTimesSection: some View {
        GroupBox("Calculated Sun Times") {
            VStack(alignment: .leading, spacing: 10) {
                AstronomyArtworkCard(
                    title: "Daylight Map",
                    subtitle: hasValidCoordinates
                        ? "A live world preview showing today’s terminator across Earth."
                        : "Enter valid coordinates to unlock the daylight preview."
                ) {
                    DaylightPreviewArtwork(
                        latitude: astronomyLatitude,
                        longitude: astronomyLongitude,
                        date: Date(),
                        isEnabled: hasValidCoordinates && !enabledSolarMoments.isEmpty
                    )
                    .aspectRatio(2.02, contentMode: .fit)
                }

                if enabledSolarMoments.isEmpty {
                    Text("Sun moments are currently hidden from Feeds.")
                        .foregroundStyle(.secondary)
                } else if let preview = nextAstronomyTimes() {
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

    private var lunarPhasesSection: some View {
        GroupBox("Calculated Moon Phases") {
            VStack(alignment: .leading, spacing: 8) {
                if showsMoonPhases {
                    astronomyPreviewLayout(preview: nextLunarPhases())
                } else {
                    Text("Moon phases are currently hidden from Feeds.")
                        .foregroundStyle(.secondary)
                }

                Text("Lunar phase changes are estimated locally from a mean synodic month and shown in your current time zone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var orbitalHighlightsSection: some View {
        let preview = nextOrbitalHighlights()

        return GroupBox("Orbital Highlights") {
            VStack(alignment: .leading, spacing: 10) {
                AstronomyArtworkCard(
                    title: "Orbital Storyboard",
                    subtitle: "Earth’s current orbital position, with the next seasonal or orbital milestone called out."
                ) {
                    OrbitalHighlightsArtwork(
                        preview: preview,
                        date: Date(),
                        isEnabled: showsOrbitalHighlights
                    )
                    .aspectRatio(2.02, contentMode: .fit)
                }

                if showsOrbitalHighlights {
                    astronomyPreviewLayout(preview: preview)
                } else {
                    Text("Orbital highlights are currently hidden from Feeds.")
                        .foregroundStyle(.secondary)
                }

                Text("Perihelion, aphelion, solstices, and equinoxes are estimated from annual orbital and seasonal formulas, then shown in your current time zone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func astronomyMomentsLayout(preview: SolarMoments) -> some View {
        let items = enabledSolarMoments.map { moment in
            (moment: moment, value: formattedAstronomyMoment(date(for: moment, in: preview), moment: moment))
        }
        astronomyInfoGrid(items: items)
    }

    private func astronomyTimeItem(moment: AstronomyMoment, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                astronomyIcon(moment: moment)
                Text(moment.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06))
                )
        )
    }

    @ViewBuilder
    private func astronomyPreviewLayout(preview: [AstronomyPreviewMoment]) -> some View {
        if preview.isEmpty {
            Text("Unavailable right now.")
                .foregroundStyle(.secondary)
        } else {
            astronomyInfoGrid(
                items: preview.map {
                    (
                        moment: $0.moment,
                        value: formattedAstronomyMoment($0.date, moment: $0.moment)
                    )
                },
            )
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

    private var hasValidCoordinates: Bool {
        (-90 ... 90).contains(astronomyLatitude) && (-180 ... 180).contains(astronomyLongitude)
    }

    private func nextAstronomyTimes() -> SolarMoments? {
        guard hasValidCoordinates else {
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

    private func nextLunarPhases() -> [AstronomyPreviewMoment] {
        nextLunarPhasesProvider(Date())
    }

    private func nextOrbitalHighlights() -> [AstronomyPreviewMoment] {
        nextOrbitalHighlightsProvider(Date())
    }

    private func astronomyInfoGrid(items: [(moment: AstronomyMoment, value: String)]) -> some View {
        ViewThatFits(in: .horizontal) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 150), spacing: 10, alignment: .leading),
                    GridItem(.flexible(minimum: 150), spacing: 10, alignment: .leading),
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(items, id: \.moment.rawValue) { item in
                    astronomyTimeItem(moment: item.moment, value: item.value)
                }
            }

            LazyVGrid(
                columns: [GridItem(.flexible(minimum: 150), spacing: 10, alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(items, id: \.moment.rawValue) { item in
                    astronomyTimeItem(moment: item.moment, value: item.value)
                }
            }
        }
    }

    private var enabledSolarMoments: [AstronomyMoment] {
        var moments: [AstronomyMoment] = []
        if showsSunriseSunset {
            moments.append(.sunrise)
        }
        if showsSolarNoonMidnight {
            moments.append(.solarNoon)
        }
        if showsSunriseSunset {
            moments.append(.sunset)
        }
        if showsSolarNoonMidnight {
            moments.append(.solarMidnight)
        }
        return moments
    }

    private func date(for moment: AstronomyMoment, in preview: SolarMoments) -> Date? {
        switch moment {
        case .sunrise:
            return preview.sunrise
        case .solarNoon:
            return preview.solarNoon
        case .sunset:
            return preview.sunset
        case .solarMidnight:
            return preview.solarMidnight
        case .perihelion, .aphelion, .marchEquinox, .juneSolstice, .septemberEquinox, .decemberSolstice, .newMoon, .waxingCrescent, .firstQuarter, .waxingGibbous, .fullMoon, .waningGibbous, .lastQuarter, .waningCrescent:
            return nil
        }
    }

    private func formattedAstronomyMoment(_ date: Date?, moment: AstronomyMoment) -> String {
        guard let date else { return "Unavailable" }
        let calendar = Calendar.current

        if AstronomyMoment.solarMoments.contains(moment) {
            if calendar.isDateInToday(date) {
                return Self.timeFormatter.string(from: date)
            }
            return "\(Self.dayFormatter.string(from: date)), \(Self.timeFormatter.string(from: date))"
        }

        if AstronomyMoment.orbitalHighlights.contains(moment),
           !calendar.isDateInToday(date),
           !calendar.isDateInTomorrow(date) {
            return Self.orbitalDateFormatter.string(from: date)
        }

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

    private static let orbitalDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct AstronomyArtworkCard<Artwork: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            artwork()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
    }
}

struct DaylightPreviewArtwork: View {
    let latitude: Double
    let longitude: Double
    let date: Date
    let isEnabled: Bool

    private struct DaylightStrip {
        let rect: CGRect
    }

    private struct DaylightSweepGeometry {
        let strips: [DaylightStrip]
        let leadingBoundarySamples: [CGPoint?]
        let trailingBoundarySamples: [CGPoint?]
    }

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            let mapRect = worldMapRect(in: rect.insetBy(dx: 2, dy: 2))

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.08, blue: 0.16),
                        Color(red: 0.02, green: 0.06, blue: 0.13),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                worldMapBackdrop(mapRect: mapRect)

                Canvas { context, size in
                    let canvasRect = CGRect(origin: .zero, size: size)
                    let canvasMapRect = worldMapRect(in: canvasRect.insetBy(dx: 2, dy: 2))
                    drawMapChrome(into: &context, mapRect: canvasMapRect)
                    drawDaylightSweep(into: &context, mapRect: canvasMapRect)
                    drawLocationMarker(into: &context, mapRect: canvasMapRect)
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(nsColor: .systemYellow),
                                        Color(nsColor: .systemOrange),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                    }
                }
                .padding(12)

                if !isEnabled {
                    Color.black.opacity(0.18)
                    Text("Enable sun moments to show this map in Feeds.")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func worldMapBackdrop(mapRect: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.12, blue: 0.20),
                            Color(red: 0.09, green: 0.15, blue: 0.24),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let worldMapImage = Self.worldMapImage {
                Image(nsImage: worldMapImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .saturation(0.22)
                    .contrast(1.08)
                    .brightness(-0.04)
                    .colorMultiply(Color(red: 0.78, green: 0.85, blue: 0.94))
                    .opacity(0.94)
            } else {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            }

            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.10, blue: 0.18).opacity(0.42),
                    Color.clear,
                    Color(red: 0.08, green: 0.14, blue: 0.23).opacity(0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .frame(width: mapRect.width, height: mapRect.height)
        .position(x: mapRect.midX, y: mapRect.midY)
    }

    private func worldMapRect(in rect: CGRect) -> CGRect {
        let availableAspect = rect.width / max(rect.height, 1)
        let targetAspect: CGFloat = Self.worldMapAspectRatio

        if availableAspect > targetAspect {
            let height = rect.height
            let width = height * targetAspect
            return CGRect(
                x: rect.midX - (width * 0.5),
                y: rect.minY,
                width: width,
                height: height
            )
        }

        let width = rect.width
        let height = width / targetAspect
        return CGRect(
            x: rect.minX,
            y: rect.midY - (height * 0.5),
            width: width,
            height: height
        )
    }

    private func drawMapChrome(into context: inout GraphicsContext, mapRect: CGRect) {
        context.fill(
            Path(mapRect),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.black.opacity(0.08), location: 0.0),
                    .init(color: Color.clear, location: 0.14),
                    .init(color: Color.clear, location: 0.86),
                    .init(color: Color.black.opacity(0.12), location: 1.0),
                ]),
                startPoint: CGPoint(x: mapRect.minX, y: mapRect.minY),
                endPoint: CGPoint(x: mapRect.maxX, y: mapRect.maxY)
            )
        )

        context.stroke(
            Path(mapRect),
            with: .color(Color.white.opacity(0.12)),
            lineWidth: 1
        )
    }

    private func drawDaylightSweep(into context: inout GraphicsContext, mapRect: CGRect) {
        let solarState = DaylightSolarState(date: date)
        let centerX = xPosition(forLongitude: solarState.subsolarLongitude, in: mapRect)
        let subsolarPoint = CGPoint(
            x: centerX,
            y: yPosition(forLatitude: solarState.declination, in: mapRect)
        )

        context.fill(
            Path(mapRect),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.black.opacity(0.28), location: 0.0),
                    .init(color: Color.black.opacity(0.16), location: 0.50),
                    .init(color: Color.black.opacity(0.28), location: 1.0),
                ]),
                startPoint: CGPoint(x: mapRect.minX, y: mapRect.minY),
                endPoint: CGPoint(x: mapRect.maxX, y: mapRect.maxY)
            )
        )

        let sweep = daylightSweepGeometry(in: mapRect, centerX: centerX, declination: solarState.declination)
        let repeatedOffsets: [CGFloat] = [-mapRect.width, 0, mapRect.width]

        for offset in repeatedOffsets {
            let daylightPath = daylightPolygonPath(from: sweep.strips, offset: offset)
            guard !daylightPath.isEmpty else { continue }

            context.blendMode = .screen
            context.fill(
                daylightPath,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.42, green: 0.57, blue: 0.84).opacity(0.20), location: 0.0),
                        .init(color: Color(red: 0.99, green: 0.76, blue: 0.39).opacity(0.28), location: 0.16),
                        .init(color: Color.white.opacity(0.16), location: 0.50),
                        .init(color: Color(red: 1.0, green: 0.77, blue: 0.38).opacity(0.28), location: 0.84),
                        .init(color: Color(red: 0.40, green: 0.55, blue: 0.82).opacity(0.20), location: 1.0),
                    ]),
                    startPoint: CGPoint(x: mapRect.minX, y: mapRect.midY),
                    endPoint: CGPoint(x: mapRect.maxX, y: mapRect.midY)
                )
            )
            context.blendMode = .normal
        }

        let glowRect = CGRect(
            x: subsolarPoint.x - (mapRect.width * 0.13),
            y: subsolarPoint.y - (mapRect.height * 0.24),
            width: mapRect.width * 0.26,
            height: mapRect.height * 0.48
        )
        context.blendMode = .screen
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(red: 1.0, green: 0.98, blue: 0.88).opacity(0.26), location: 0.0),
                    .init(color: Color(red: 1.0, green: 0.84, blue: 0.52).opacity(0.14), location: 0.42),
                    .init(color: .clear, location: 1.0),
                ]),
                center: subsolarPoint,
                startRadius: 0,
                endRadius: max(glowRect.width, glowRect.height) * 0.55
            )
        )
        context.blendMode = .normal

        let leadingBoundary = daylightBoundaryPath(
            from: sweep.leadingBoundarySamples,
            jumpThreshold: mapRect.width * 0.28
        )
        let trailingBoundary = daylightBoundaryPath(
            from: sweep.trailingBoundarySamples,
            jumpThreshold: mapRect.width * 0.28
        )

        for offset in repeatedOffsets {
            let transform = CGAffineTransform(translationX: offset, y: 0)
            context.stroke(
                leadingBoundary.applying(transform),
                with: .color(Color.white.opacity(0.12)),
                lineWidth: 1.0
            )
            context.stroke(
                trailingBoundary.applying(transform),
                with: .color(Color.white.opacity(0.12)),
                lineWidth: 1.0
            )
            context.stroke(
                leadingBoundary.applying(transform),
                with: .color(Color(red: 0.72, green: 0.84, blue: 1.0).opacity(0.36)),
                lineWidth: 2.6
            )
            context.stroke(
                trailingBoundary.applying(transform),
                with: .color(Color(red: 1.0, green: 0.70, blue: 0.32).opacity(0.40)),
                lineWidth: 2.8
            )
        }
    }

    private func drawLocationMarker(into context: inout GraphicsContext, mapRect: CGRect) {
        let point = CGPoint(
            x: xPosition(forLongitude: longitude, in: mapRect),
            y: yPosition(forLatitude: latitude, in: mapRect)
        )

        let glowRect = CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)
        context.fill(Path(ellipseIn: glowRect), with: .color(Color.white.opacity(0.12)))

        let outerRect = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
        context.fill(Path(ellipseIn: outerRect), with: .color(Color.black.opacity(0.55)))
        context.stroke(Path(ellipseIn: outerRect), with: .color(Color.white.opacity(0.95)), lineWidth: 1.2)

        let centerRect = CGRect(x: point.x - 1.75, y: point.y - 1.75, width: 3.5, height: 3.5)
        context.fill(
            Path(ellipseIn: centerRect),
            with: .color(Color(nsColor: .systemYellow))
        )
    }

    private func xPosition(forLongitude longitude: Double, in rect: CGRect) -> CGFloat {
        let normalizedLongitude = normalizedWrappedLongitude(longitude)
        return rect.minX + (CGFloat((normalizedLongitude + 180.0) / 360.0) * rect.width)
    }

    private func yPosition(forLatitude latitude: Double, in rect: CGRect) -> CGFloat {
        let clampedLatitude = max(-90.0, min(90.0, latitude))
        let normalizedY = CGFloat((90.0 - clampedLatitude) / 180.0)
        return rect.minY + (normalizedY * rect.height)
    }

    private func latitude(forY y: CGFloat, in rect: CGRect) -> Double {
        let normalizedY = min(max((y - rect.minY) / rect.height, 0), 1)
        return 90.0 - (Double(normalizedY) * 180.0)
    }

    private func normalizedWrappedLongitude(_ longitude: Double) -> Double {
        var value = longitude.truncatingRemainder(dividingBy: 360.0)
        if value > 180.0 {
            value -= 360.0
        } else if value < -180.0 {
            value += 360.0
        }
        return value
    }

    private func daylightSweepGeometry(in rect: CGRect, centerX: CGFloat, declination: Double) -> DaylightSweepGeometry {
        let sampleCount = max(96, Int(rect.height * 0.9))
        let rowHeight = rect.height / CGFloat(sampleCount)
        var strips: [DaylightStrip] = []
        var leadingBoundarySamples: [CGPoint?] = []
        var trailingBoundarySamples: [CGPoint?] = []

        strips.reserveCapacity(sampleCount)
        leadingBoundarySamples.reserveCapacity(sampleCount)
        trailingBoundarySamples.reserveCapacity(sampleCount)

        for index in 0 ..< sampleCount {
            let y = rect.minY + (CGFloat(index) * rowHeight)
            let sampleY = min(rect.maxY, y + (rowHeight * 0.5))
            let latitude = latitude(forY: sampleY, in: rect)

            guard let interval = daylightInterval(
                forLatitude: latitude,
                centerX: centerX,
                declination: declination,
                rect: rect
            ) else {
                leadingBoundarySamples.append(nil)
                trailingBoundarySamples.append(nil)
                continue
            }

            strips.append(
                DaylightStrip(
                    rect: CGRect(
                        x: interval.startX,
                        y: y,
                        width: interval.endX - interval.startX,
                        height: rowHeight + 0.9
                    )
                )
            )

            if let leadingX = interval.leadingBoundaryX,
               let trailingX = interval.trailingBoundaryX {
                leadingBoundarySamples.append(CGPoint(x: leadingX, y: sampleY))
                trailingBoundarySamples.append(CGPoint(x: trailingX, y: sampleY))
            } else {
                leadingBoundarySamples.append(nil)
                trailingBoundarySamples.append(nil)
            }
        }

        return DaylightSweepGeometry(
            strips: strips,
            leadingBoundarySamples: leadingBoundarySamples,
            trailingBoundarySamples: trailingBoundarySamples
        )
    }

    private func daylightInterval(
        forLatitude latitude: Double,
        centerX: CGFloat,
        declination: Double,
        rect: CGRect
    ) -> (startX: CGFloat, endX: CGFloat, leadingBoundaryX: CGFloat?, trailingBoundaryX: CGFloat?)? {
        let latitudeRadians = latitude * .pi / 180.0
        let declinationRadians = declination * .pi / 180.0
        let sunriseCosine = -tan(latitudeRadians) * tan(declinationRadians)

        if sunriseCosine >= 1 {
            return nil
        }

        let daylightArcDegrees: Double
        let hasVisibleTerminator: Bool
        if sunriseCosine <= -1 {
            daylightArcDegrees = 180.0
            hasVisibleTerminator = false
        } else {
            daylightArcDegrees = acos(sunriseCosine) * 180.0 / .pi
            hasVisibleTerminator = true
        }

        let halfWidth = rect.width * CGFloat(daylightArcDegrees / 360.0)
        return (
            startX: centerX - halfWidth,
            endX: centerX + halfWidth,
            leadingBoundaryX: hasVisibleTerminator ? centerX - halfWidth : nil,
            trailingBoundaryX: hasVisibleTerminator ? centerX + halfWidth : nil
        )
    }

    private func daylightBoundaryPath(from samples: [CGPoint?], jumpThreshold: CGFloat) -> Path {
        var path = Path()
        var previousPoint: CGPoint?

        for sample in samples {
            guard let point = sample else {
                previousPoint = nil
                continue
            }

            if let previousPoint,
               abs(point.x - previousPoint.x) <= jumpThreshold {
                path.addLine(to: point)
            } else {
                path.move(to: point)
            }

            previousPoint = point
        }

        return path
    }

    private func daylightPolygonPath(from strips: [DaylightStrip], offset: CGFloat) -> Path {
        var path = Path()
        guard let firstStrip = strips.first else { return path }

        path.move(to: CGPoint(x: firstStrip.rect.minX + offset, y: firstStrip.rect.minY))
        for strip in strips {
            path.addLine(to: CGPoint(x: strip.rect.minX + offset, y: strip.rect.maxY))
        }
        for strip in strips.reversed() {
            path.addLine(to: CGPoint(x: strip.rect.maxX + offset, y: strip.rect.maxY))
            path.addLine(to: CGPoint(x: strip.rect.maxX + offset, y: strip.rect.minY))
        }
        path.closeSubpath()
        return path
    }

    private static let worldMapAspectRatio: CGFloat = 2.0
    private static let worldMapImage: NSImage? = {
        let bundle = Bundle.module
        let candidateURLs = [
            bundle.url(forResource: "earth-blue-marble", withExtension: "png"),
            bundle.url(forResource: "earth-blue-marble", withExtension: "png", subdirectory: "Resources/Images"),
        ]

        for url in candidateURLs.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }()
}

private struct OrbitalHighlightsArtwork: View {
    let preview: [SettingsAstronomySectionView.AstronomyPreviewMoment]
    let date: Date
    let isEnabled: Bool

    private struct OrbitalGeometry {
        let center: CGPoint
        let semiMajorAxis: CGFloat
        let semiMinorAxis: CGFloat
        let focusOffset: CGFloat

        var rect: CGRect {
            CGRect(
                x: center.x - semiMajorAxis,
                y: center.y - semiMinorAxis,
                width: semiMajorAxis * 2,
                height: semiMinorAxis * 2
            )
        }

        var sunCenter: CGPoint {
            CGPoint(x: center.x - focusOffset, y: center.y)
        }
    }

    private struct OrbitalMilestone {
        let moment: AstronomyMoment
        let date: Date
        let label: String
        let color: Color
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                drawBackground(into: &context, rect: rect)
                drawStars(into: &context, rect: rect)
                let geometry = orbitGeometry(in: rect)
                let milestones = orbitalMilestones(for: date)
                drawOrbit(into: &context, geometry: geometry)
                drawOrbitProgress(into: &context, geometry: geometry)
                drawSun(into: &context, center: geometry.sunCenter)
                drawMilestones(into: &context, geometry: geometry, milestones: milestones)
                drawCurrentPosition(into: &context, geometry: geometry)
            }

            VStack {
                HStack {
                    if let next = preview.first {
                        highlightPill(
                            title: next.moment.title,
                            subtitle: formattedUpcomingHighlight(next.date)
                        )
                    } else {
                        highlightPill(
                            title: "Orbital Highlights",
                            subtitle: "Current position around the Sun"
                        )
                    }
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    highlightPill(
                        title: "Now",
                        subtitle: orbitProgressSummary
                    )
                }
            }
            .padding(12)

            if !isEnabled {
                Color.black.opacity(0.18)
                Text("Enable orbital highlights to show these milestones in Feeds.")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    private func drawBackground(into context: inout GraphicsContext, rect: CGRect) {
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.11),
                    Color(red: 0.07, green: 0.10, blue: 0.20),
                    Color(red: 0.04, green: 0.06, blue: 0.14),
                ]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        )
    }

    private func drawStars(into context: inout GraphicsContext, rect: CGRect) {
        for star in Self.starField {
            let point = CGPoint(x: rect.minX + (star.x * rect.width), y: rect.minY + (star.y * rect.height))
            let starRect = CGRect(x: point.x - star.size / 2, y: point.y - star.size / 2, width: star.size, height: star.size)
            context.fill(Path(ellipseIn: starRect), with: .color(Color.white.opacity(star.opacity)))
        }
    }

    private func orbitGeometry(in rect: CGRect) -> OrbitalGeometry {
        let horizontalInset = rect.width * 0.12
        let verticalInset = rect.height * 0.15
        let availableWidth = max(120, rect.width - (horizontalInset * 2))
        let availableHeight = max(120, rect.height - (verticalInset * 2))
        let semiMajorAxis = min(availableWidth * 0.5, availableHeight * 0.5 / Self.earthOrbitAxisRatio)
        let semiMinorAxis = semiMajorAxis * Self.earthOrbitAxisRatio

        return OrbitalGeometry(
            center: CGPoint(x: rect.midX, y: rect.midY),
            semiMajorAxis: semiMajorAxis,
            semiMinorAxis: semiMinorAxis,
            focusOffset: semiMajorAxis * Self.earthOrbitEccentricity
        )
    }

    private func drawOrbit(into context: inout GraphicsContext, geometry: OrbitalGeometry) {
        context.stroke(
            Path(ellipseIn: geometry.rect),
            with: .color(Color.white.opacity(0.18)),
            style: StrokeStyle(lineWidth: 2)
        )
    }

    private func drawOrbitProgress(into context: inout GraphicsContext, geometry: OrbitalGeometry) {
        let progressPath = orbitalProgressPath(in: geometry, endDate: date)
        context.stroke(
            progressPath,
            with: .color(Color(nsColor: .systemOrange).opacity(0.75)),
            style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawSun(into context: inout GraphicsContext, center: CGPoint) {
        let glowRect = CGRect(x: center.x - 24, y: center.y - 24, width: 48, height: 48)
        let coreRect = CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)
        context.fill(Path(ellipseIn: glowRect), with: .color(Color(nsColor: .systemOrange).opacity(0.26)))
        context.fill(Path(ellipseIn: coreRect), with: .color(Color(nsColor: .systemYellow)))
    }

    private func drawMilestones(
        into context: inout GraphicsContext,
        geometry: OrbitalGeometry,
        milestones: [OrbitalMilestone]
    ) {
        for milestone in milestones {
            let point = pointOnOrbit(in: geometry, date: milestone.date)
            let markerRect = CGRect(x: point.x - 4.6, y: point.y - 4.6, width: 9.2, height: 9.2)
            context.fill(Path(ellipseIn: markerRect), with: .color(milestone.color.opacity(0.96)))
            context.stroke(Path(ellipseIn: markerRect), with: .color(Color.white.opacity(0.72)), lineWidth: 1)
            drawMilestoneLabel(into: &context, point: point, milestone: milestone)
        }
    }

    private func drawMilestoneLabel(
        into context: inout GraphicsContext,
        point: CGPoint,
        milestone: OrbitalMilestone
    ) {
        let layout = milestoneLabelLayout(for: milestone.moment)
        let drawPoint = CGPoint(
            x: point.x + layout.offset.width,
            y: point.y + layout.offset.height
        )

        context.draw(
            Text(milestone.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.78)),
            at: drawPoint,
            anchor: layout.anchor
        )
    }

    private func drawCurrentPosition(
        into context: inout GraphicsContext,
        geometry: OrbitalGeometry
    ) {
        let point = pointOnOrbit(in: geometry, date: date)

        var beam = Path()
        beam.move(to: geometry.sunCenter)
        beam.addLine(to: point)
        context.stroke(beam, with: .color(Color.white.opacity(0.18)), lineWidth: 1.2)

        let glowRect = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
        let outerRect = CGRect(x: point.x - 6.5, y: point.y - 6.5, width: 13, height: 13)
        let coreRect = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
        context.fill(Path(ellipseIn: glowRect), with: .color(Color.white.opacity(0.14)))
        context.fill(Path(ellipseIn: outerRect), with: .color(Color(red: 0.14, green: 0.29, blue: 0.62)))
        context.fill(Path(ellipseIn: coreRect), with: .color(Color(red: 0.34, green: 0.71, blue: 0.42)))
        context.stroke(Path(ellipseIn: outerRect), with: .color(Color.white.opacity(0.85)), lineWidth: 1.1)

        let layout = annotationLayout(for: point, center: geometry.center)

        context.draw(
            Text("Now")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.92)),
            at: CGPoint(x: point.x + layout.offset.width, y: point.y + layout.offset.height),
            anchor: layout.anchor
        )
    }

    private func milestoneLabelLayout(for moment: AstronomyMoment) -> (offset: CGSize, anchor: UnitPoint) {
        switch moment {
        case .perihelion:
            return (CGSize(width: -12, height: 12), .topTrailing)
        case .marchEquinox:
            return (CGSize(width: 0, height: -12), .bottom)
        case .juneSolstice:
            return (CGSize(width: 14, height: -10), .bottomLeading)
        case .aphelion:
            return (CGSize(width: 14, height: 8), .topLeading)
        case .septemberEquinox:
            return (CGSize(width: 0, height: 14), .top)
        case .decemberSolstice:
            return (CGSize(width: -12, height: 10), .topTrailing)
        default:
            return (CGSize(width: 12, height: -12), .bottomLeading)
        }
    }

    private func annotationLayout(for point: CGPoint, center: CGPoint) -> (offset: CGSize, anchor: UnitPoint) {
        let isLeadingSide = point.x <= center.x
        let isTopSide = point.y <= center.y

        switch (isLeadingSide, isTopSide) {
        case (true, true):
            return (CGSize(width: -12, height: -12), .bottomTrailing)
        case (true, false):
            return (CGSize(width: -12, height: 12), .topTrailing)
        case (false, true):
            return (CGSize(width: 12, height: -12), .bottomLeading)
        case (false, false):
            return (CGSize(width: 12, height: 12), .topLeading)
        }
    }

    private func pointOnOrbit(in geometry: OrbitalGeometry, phase: CGFloat) -> CGPoint {
        CGPoint(
            x: geometry.center.x + (cos(phase) * geometry.semiMajorAxis),
            y: geometry.center.y + (sin(phase) * geometry.semiMinorAxis)
        )
    }

    private func pointOnOrbit(in geometry: OrbitalGeometry, date: Date) -> CGPoint {
        pointOnOrbit(in: geometry, phase: orbitalPhase(for: date))
    }

    private func orbitalProgressPath(in geometry: OrbitalGeometry, endDate: Date) -> Path {
        var path = Path()
        let endAnomaly = orbitalEccentricAnomaly(for: endDate)
        let samples = 120

        for index in 0 ... samples {
            let progress = CGFloat(index) / CGFloat(samples)
            let anomaly = CGFloat(endAnomaly) * progress
            let point = pointOnOrbit(in: geometry, phase: .pi + anomaly)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func orbitalPhase(for date: Date) -> CGFloat {
        .pi + CGFloat(orbitalEccentricAnomaly(for: date))
    }

    private func orbitalEccentricAnomaly(for date: Date) -> Double {
        let meanAnomaly = orbitalProgress(for: date) * .pi * 2
        var eccentricAnomaly = meanAnomaly

        for _ in 0 ..< 6 {
            let numerator = eccentricAnomaly - (Self.earthOrbitEccentricity * sin(eccentricAnomaly)) - meanAnomaly
            let denominator = max(0.0001, 1 - (Self.earthOrbitEccentricity * cos(eccentricAnomaly)))
            eccentricAnomaly -= numerator / denominator
        }

        return eccentricAnomaly
    }

    private func orbitalProgress(for date: Date) -> Double {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let referencePerihelion = calendar.date(from: DateComponents(year: year, month: 1, day: 3, hour: 0)) ?? date
        let nextPerihelion = calendar.date(byAdding: .year, value: 1, to: referencePerihelion) ?? referencePerihelion.addingTimeInterval(365.2422 * 86_400)
        let cycleDuration = max(1, nextPerihelion.timeIntervalSince(referencePerihelion))
        let normalizedProgress = ((date.timeIntervalSince(referencePerihelion) / cycleDuration).truncatingRemainder(dividingBy: 1) + 1)
            .truncatingRemainder(dividingBy: 1)
        return normalizedProgress
    }

    private func orbitalMilestones(for date: Date) -> [OrbitalMilestone] {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)

        let definitions: [(AstronomyMoment, DateComponents, String, NSColor)] = [
            (.perihelion, DateComponents(year: year, month: 1, day: 3, hour: 0), "Peri", .systemYellow),
            (.marchEquinox, DateComponents(year: year, month: 3, day: 20, hour: 0), "Mar Eq.", .systemGreen),
            (.juneSolstice, DateComponents(year: year, month: 6, day: 21, hour: 0), "Jun Sol.", .systemTeal),
            (.aphelion, DateComponents(year: year, month: 7, day: 4, hour: 0), "Aphe", .systemBlue),
            (.septemberEquinox, DateComponents(year: year, month: 9, day: 22, hour: 0), "Sep Eq.", .systemOrange),
            (.decemberSolstice, DateComponents(year: year, month: 12, day: 21, hour: 0), "Dec Sol.", .systemPurple),
        ]

        return definitions.compactMap { moment, components, label, color in
            guard let eventDate = calendar.date(from: components) else { return nil }
            return OrbitalMilestone(
                moment: moment,
                date: eventDate,
                label: label,
                color: Color(nsColor: color)
            )
        }
    }

    private func formattedUpcomingHighlight(_ date: Date) -> String {
        Self.highlightFormatter.string(from: date)
    }

    private var orbitProgressSummary: String {
        "\(Int((orbitalProgress(for: date) * 100).rounded()))% of current solar year"
    }

    private static let starField: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.08, 0.14, 2.0, 0.70), (0.16, 0.70, 1.6, 0.52), (0.28, 0.12, 1.4, 0.56),
        (0.38, 0.82, 1.8, 0.44), (0.48, 0.18, 2.2, 0.68), (0.58, 0.66, 1.4, 0.55),
        (0.72, 0.24, 1.8, 0.48), (0.82, 0.74, 2.0, 0.60), (0.90, 0.18, 1.6, 0.52),
    ]
    private static let earthOrbitEccentricity: CGFloat = 0.0167
    private static let earthOrbitAxisRatio = sqrt(1 - (earthOrbitEccentricity * earthOrbitEccentricity))

    private static let highlightFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct DaylightSolarState {
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

private func highlightPill(title: String, subtitle: String) -> some View {
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
