import AppKit
import Foundation

enum AstronomyMoment: String, CaseIterable {
    case sunrise = "sunrise"
    case solarNoon = "solar noon"
    case sunset = "sunset"
    case solarMidnight = "solar midnight"
    case perihelion = "perihelion"
    case aphelion = "aphelion"
    case marchEquinox = "march equinox"
    case juneSolstice = "june solstice"
    case septemberEquinox = "september equinox"
    case decemberSolstice = "december solstice"
    case newMoon = "new moon"
    case waxingCrescent = "waxing crescent"
    case firstQuarter = "first quarter"
    case waxingGibbous = "waxing gibbous"
    case fullMoon = "full moon"
    case waningGibbous = "waning gibbous"
    case lastQuarter = "last quarter"
    case waningCrescent = "waning crescent"

    init?(eventTitle: String) {
        let normalized = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.init(rawValue: normalized)
    }

    var title: String {
        switch self {
        case .sunrise:
            return "Sunrise"
        case .solarNoon:
            return "Solar Noon"
        case .sunset:
            return "Sunset"
        case .solarMidnight:
            return "Solar Midnight"
        case .perihelion:
            return "Perihelion"
        case .aphelion:
            return "Aphelion"
        case .marchEquinox:
            return "March Equinox"
        case .juneSolstice:
            return "June Solstice"
        case .septemberEquinox:
            return "September Equinox"
        case .decemberSolstice:
            return "December Solstice"
        case .newMoon:
            return "New Moon"
        case .waxingCrescent:
            return "Waxing Crescent"
        case .firstQuarter:
            return "First Quarter"
        case .waxingGibbous:
            return "Waxing Gibbous"
        case .fullMoon:
            return "Full Moon"
        case .waningGibbous:
            return "Waning Gibbous"
        case .lastQuarter:
            return "Last Quarter"
        case .waningCrescent:
            return "Waning Crescent"
        }
    }

    var fallbackSymbolName: String {
        switch self {
        case .sunrise:
            return "sunrise.fill"
        case .solarNoon:
            return "sun.max.fill"
        case .sunset:
            return "sunset.fill"
        case .solarMidnight:
            return "moon.stars.fill"
        case .perihelion:
            return "sun.max.fill"
        case .aphelion:
            return "sun.max.circle.fill"
        case .marchEquinox:
            return "leaf.fill"
        case .juneSolstice:
            return "sun.max.fill"
        case .septemberEquinox:
            return "leaf.circle.fill"
        case .decemberSolstice:
            return "snowflake"
        case .newMoon:
            return "moonphase.new.moon"
        case .waxingCrescent:
            return "moonphase.waxing.crescent"
        case .firstQuarter:
            return "moonphase.first.quarter"
        case .waxingGibbous:
            return "moonphase.waxing.gibbous"
        case .fullMoon:
            return "moonphase.full.moon"
        case .waningGibbous:
            return "moonphase.waning.gibbous"
        case .lastQuarter:
            return "moonphase.last.quarter"
        case .waningCrescent:
            return "moonphase.waning.crescent"
        }
    }

    var svgAssetName: String? {
        switch self {
        case .solarNoon:
            return "solar-noon"
        case .solarMidnight:
            return "solar-midnight"
        case .newMoon:
            return "moon-new"
        case .waxingCrescent:
            return "moon-waxing-crescent"
        case .firstQuarter:
            return "moon-first-quarter"
        case .waxingGibbous:
            return "moon-waxing-gibbous"
        case .fullMoon:
            return "moon-full"
        case .waningGibbous:
            return "moon-waning-gibbous"
        case .lastQuarter:
            return "moon-last-quarter"
        case .waningCrescent:
            return "moon-waning-crescent"
        case .sunrise, .sunset, .perihelion, .aphelion, .marchEquinox, .juneSolstice, .septemberEquinox, .decemberSolstice:
            return nil
        }
    }

    static let solarMoments: [AstronomyMoment] = [
        .sunrise,
        .solarNoon,
        .sunset,
        .solarMidnight,
    ]

    static let orbitalMoments: [AstronomyMoment] = [
        .perihelion,
        .aphelion,
    ]

    static let seasonalMoments: [AstronomyMoment] = [
        .marchEquinox,
        .juneSolstice,
        .septemberEquinox,
        .decemberSolstice,
    ]

    static let orbitalHighlights: [AstronomyMoment] = orbitalMoments + seasonalMoments

    static let lunarPhases: [AstronomyMoment] = [
        .newMoon,
        .waxingCrescent,
        .firstQuarter,
        .waxingGibbous,
        .fullMoon,
        .waningGibbous,
        .lastQuarter,
        .waningCrescent,
    ]

    var menuMarkerStyle: MenuMarkerStyle {
        switch self {
        case .sunrise:
            return .sunrise
        case .solarNoon:
            return .solarNoon
        case .sunset:
            return .sunset
        case .solarMidnight:
            return .solarMidnight
        case .perihelion:
            return .perihelion
        case .aphelion:
            return .aphelion
        case .marchEquinox:
            return .marchEquinox
        case .juneSolstice:
            return .juneSolstice
        case .septemberEquinox:
            return .septemberEquinox
        case .decemberSolstice:
            return .decemberSolstice
        case .newMoon:
            return .newMoon
        case .waxingCrescent:
            return .waxingCrescent
        case .firstQuarter:
            return .firstQuarter
        case .waxingGibbous:
            return .waxingGibbous
        case .fullMoon:
            return .fullMoon
        case .waningGibbous:
            return .waningGibbous
        case .lastQuarter:
            return .lastQuarter
        case .waningCrescent:
            return .waningCrescent
        }
    }
}

enum AstronomyIconProvider {
    static func image(for moment: AstronomyMoment, pointSize: CGFloat) -> NSImage? {
        if let svgAssetName = moment.svgAssetName,
           let svg = svgImage(named: svgAssetName) {
            svg.size = NSSize(width: pointSize, height: pointSize)
            svg.isTemplate = false
            return svg
        }

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration.preferringMulticolor())

        if let symbol = NSImage(systemSymbolName: moment.fallbackSymbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            symbol.isTemplate = false
            return symbol
        }

        return nil
    }

    private static func svgImage(named name: String) -> NSImage? {
        let url = Bundle.module.url(forResource: name, withExtension: "svg")
            ?? Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Resources/Images")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}
