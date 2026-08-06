import AppKit
import SwiftUI

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

    private var previewReferenceDate: Date {
        AlertCalendarClock.nowRoundedToSecond()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeaderView(title: title)

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
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var astronomyTimesSection: some View {
        previewPanel("Calculated Sun Times") {
            VStack(alignment: .leading, spacing: 10) {
                DaylightPreviewArtwork(
                    latitude: astronomyLatitude,
                    longitude: astronomyLongitude,
                    date: previewReferenceDate,
                    isEnabled: hasValidCoordinates && !enabledSolarMoments.isEmpty
                )
                .aspectRatio(DaylightPreviewArtwork.preferredAspectRatio, contentMode: ContentMode.fit)

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
        previewPanel("Calculated Moon Phases") {
            VStack(alignment: .leading, spacing: 8) {
                if showsMoonPhases {
                    astronomyPreviewLayout(preview: nextLunarPhases(), maximumColumns: 8)
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

        return previewPanel("Orbital Highlights") {
            VStack(alignment: .leading, spacing: 10) {
                OrbitalHighlightsArtwork(
                    preview: preview,
                    date: previewReferenceDate,
                    isEnabled: showsOrbitalHighlights
                )
                .aspectRatio(2.02, contentMode: ContentMode.fit)

                if showsOrbitalHighlights {
                    astronomyPreviewLayout(preview: preview, maximumColumns: 3)
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

    private func previewPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(SettingsTypography.panelTitle)
                .foregroundStyle(.primary)

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
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
                .font(SettingsTypography.prominentValue)
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
    private func astronomyPreviewLayout(
        preview: [AstronomyPreviewMoment],
        maximumColumns: Int = 4
    ) -> some View {
        if preview.isEmpty {
            Text("Unavailable right now.")
                .foregroundStyle(.secondary)
        } else {
            astronomyInfoGrid(
                maximumColumns: maximumColumns,
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

        let now = previewReferenceDate
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
        nextLunarPhasesProvider(previewReferenceDate)
    }

    private func nextOrbitalHighlights() -> [AstronomyPreviewMoment] {
        nextOrbitalHighlightsProvider(previewReferenceDate)
    }

    private func astronomyInfoGrid(
        maximumColumns: Int = 4,
        items: [(moment: AstronomyMoment, value: String)]
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            if maximumColumns >= 8 {
                astronomyInfoGridLayout(columns: 8, items: items)
            }
            if maximumColumns >= 7 {
                astronomyInfoGridLayout(columns: 7, items: items)
            }
            if maximumColumns >= 6 {
                astronomyInfoGridLayout(columns: 6, items: items)
            }
            if maximumColumns >= 5 {
                astronomyInfoGridLayout(columns: 5, items: items)
            }
            if maximumColumns >= 4 {
                astronomyInfoGridLayout(columns: 4, items: items)
            }
            if maximumColumns >= 3 {
                astronomyInfoGridLayout(columns: 3, items: items)
            }
            if maximumColumns >= 2 {
                astronomyInfoGridLayout(columns: 2, items: items)
            }
            astronomyInfoGridLayout(columns: 1, items: items)
        }
    }

    private func astronomyInfoGridLayout(
        columns columnCount: Int,
        items: [(moment: AstronomyMoment, value: String)]
    ) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 150), spacing: 10, alignment: .leading),
            count: columnCount
        )

        return LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(items, id: \.moment.rawValue) { item in
                astronomyTimeItem(moment: item.moment, value: item.value)
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
            if calendar.isDateInTomorrow(date) {
                return "Tomorrow, \(Self.timeFormatter.string(from: date))"
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
