import XCTest
@testable import AlertCalendar

final class WeatherObservationTests: XCTestCase {
    func testWeatherObservationClassifierPrefersWeatherCodeForTitles() {
        XCTAssertEqual(WeatherObservationClassifier.title(for: 95, precipitationAmount: 0.2), "Thunderstorm")
        XCTAssertEqual(WeatherObservationClassifier.title(for: 80, precipitationAmount: 0.2), "Rain")
        XCTAssertEqual(WeatherObservationClassifier.title(for: 51, precipitationAmount: 0.2), "Drizzle")
    }

    func testWeatherObservationClassifierFallsBackToPrecipitationAmount() {
        XCTAssertEqual(WeatherObservationClassifier.title(for: nil, precipitationAmount: 0.1), "Drizzle")
        XCTAssertEqual(WeatherObservationClassifier.title(for: nil, precipitationAmount: 0.6), "Rain")
        XCTAssertEqual(WeatherObservationClassifier.title(for: nil, precipitationAmount: 2.4), "Thunderstorm")
    }

    func testEffectiveRainAmountUsesShowersWhenRainIsZero() {
        XCTAssertEqual(
            WeatherObservationClassifier.effectiveRainAmount(
                precipitation: 0,
                rain: 0,
                showers: 0.8,
                weatherCode: 80
            ),
            0.8
        )
    }

    func testEffectiveRainAmountUsesPrecipitationFallbackForRainCodes() {
        XCTAssertEqual(
            WeatherObservationClassifier.effectiveRainAmount(
                precipitation: 1.2,
                rain: 0,
                showers: nil,
                weatherCode: 61
            ),
            1.2
        )
    }

    func testEffectiveRainAmountIgnoresNonRainPrecipitationCodes() {
        XCTAssertEqual(
            WeatherObservationClassifier.effectiveRainAmount(
                precipitation: 1.2,
                rain: 0,
                showers: nil,
                weatherCode: 71
            ),
            0
        )
    }
}
