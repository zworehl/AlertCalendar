import AppKit
import Foundation

enum AstronomyMoment: String, CaseIterable {
    case sunrise = "sunrise"
    case solarNoon = "solar noon"
    case sunset = "sunset"
    case solarMidnight = "solar midnight"

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
        }
    }

    var svgAssetName: String? {
        switch self {
        case .solarNoon:
            return "solar-noon"
        case .solarMidnight:
            return "solar-midnight"
        case .sunrise, .sunset:
            return nil
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
