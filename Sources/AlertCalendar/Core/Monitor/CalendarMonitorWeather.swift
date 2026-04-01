import AppKit
import Foundation

extension CalendarMonitor {
    private static let rainObservationIntervals = 672

    func loadWeatherRainItem(now: Date, end: Date, settings: SettingsSnapshot) async -> UpcomingItem? {
        guard (-90 ... 90).contains(settings.astronomyLatitude),
              (-180 ... 180).contains(settings.astronomyLongitude) else {
            return nil
        }

        let observation = WeatherObservationService()

        do {
            guard let segment = try await observation.fetchNearestRainSegment(
                now: now,
                lookAheadEnd: end,
                latitude: settings.astronomyLatitude,
                longitude: settings.astronomyLongitude,
                forecastIntervals: Self.rainObservationIntervals,
                pastIntervals: Self.rainObservationIntervals
            ) else {
                return nil
            }

            return UpcomingItem(
                id: "weather-rain-\(Int(segment.start.timeIntervalSince1970))",
                title: weatherTitle(
                    for: segment.dominantWeatherCode,
                    precipitationAmount: segment.peakPrecipitationAmount
                ),
                date: segment.start,
                endDate: segment.end,
                isAllDay: false,
                showsMutedBackground: false,
                travelTimeMinutes: nil,
                locationText: "\(settings.astronomyLatitude), \(settings.astronomyLongitude)",
                meetingURL: nil,
                calendarID: nil,
                calendarName: "Weather",
                calendarColor: NSColor.systemTeal,
                kind: .weather,
                footballMatch: nil,
                footballMenuBarDisplay: nil
            )
        } catch {
            return nil
        }
    }

    func weatherTitle(for weatherCode: Int?, precipitationAmount: Double) -> String {
        WeatherObservationClassifier.title(for: weatherCode, precipitationAmount: precipitationAmount)
    }

    func weatherTitle(for rainAmount: Double) -> String {
        WeatherObservationClassifier.title(for: nil, precipitationAmount: rainAmount)
    }
}

enum WeatherObservationClassifier {
    static func title(for weatherCode: Int?, precipitationAmount: Double) -> String {
        switch category(for: weatherCode) {
        case .thunderstorm:
            return "Thunderstorm"
        case .rain:
            return "Rain"
        case .drizzle:
            return "Drizzle"
        case .none:
            return fallbackTitle(for: precipitationAmount)
        }
    }

    static func effectiveRainAmount(
        precipitation: Double,
        rain: Double,
        showers: Double?,
        weatherCode: Int?
    ) -> Double {
        let rainAmount = max(rain, showers ?? 0)
        if rainAmount > 0 {
            return rainAmount
        }

        guard precipitation > 0, shouldTreatPrecipitationAsRain(weatherCode: weatherCode) else {
            return 0
        }
        return precipitation
    }

    static func priority(for weatherCode: Int) -> Int {
        switch category(for: weatherCode) {
        case .thunderstorm:
            return 3
        case .rain:
            return 2
        case .drizzle:
            return 1
        case .none:
            return 0
        }
    }

    private enum Category {
        case none
        case drizzle
        case rain
        case thunderstorm
    }

    private static func category(for weatherCode: Int?) -> Category {
        guard let weatherCode else { return .none }

        switch weatherCode {
        case 95, 96, 99:
            return .thunderstorm
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return .rain
        case 51, 53, 55, 56, 57:
            return .drizzle
        default:
            return .none
        }
    }

    private static func shouldTreatPrecipitationAsRain(weatherCode: Int?) -> Bool {
        guard let weatherCode else { return true }
        return category(for: weatherCode) != .none
    }

    private static func fallbackTitle(for precipitationAmount: Double) -> String {
        if precipitationAmount >= 2.0 {
            return "Thunderstorm"
        }
        if precipitationAmount >= 0.5 {
            return "Rain"
        }
        return "Drizzle"
    }
}

private struct OpenMeteoRainResponse: Decodable {
    let minutely15: OpenMeteoRainWindow?

    enum CodingKeys: String, CodingKey {
        case minutely15 = "minutely_15"
    }
}

private struct OpenMeteoRainWindow: Decodable {
    let time: [Int]
    let precipitation: [Double]
    let rain: [Double]
    let showers: [Double]?
    let weatherCode: [Int]?

    enum CodingKeys: String, CodingKey {
        case time
        case precipitation
        case rain
        case showers
        case weatherCode = "weather_code"
    }

    func effectiveRainAmount(at index: Int) -> Double {
        WeatherObservationClassifier.effectiveRainAmount(
            precipitation: precipitation[index],
            rain: rain[index],
            showers: showersValue(at: index),
            weatherCode: weatherCodeValue(at: index)
        )
    }

    func weatherCodeValue(at index: Int) -> Int? {
        guard let weatherCode, weatherCode.indices.contains(index) else { return nil }
        return weatherCode[index]
    }

    private func showersValue(at index: Int) -> Double? {
        guard let showers, showers.indices.contains(index) else { return nil }
        return showers[index]
    }
}

private struct WeatherSegment {
    let start: Date
    let end: Date
    let peakPrecipitationAmount: Double
    let dominantWeatherCode: Int?
}

private struct WeatherObservationService {
    func fetchNearestRainSegment(
        now: Date,
        lookAheadEnd: Date,
        latitude: Double,
        longitude: Double,
        forecastIntervals: Int,
        pastIntervals: Int
    ) async throws -> WeatherSegment? {
        let url = try buildURL(
            latitude: latitude,
            longitude: longitude,
            forecastIntervals: forecastIntervals,
            pastIntervals: pastIntervals
        )
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(OpenMeteoRainResponse.self, from: data)
        guard let minutely = decoded.minutely15 else { return nil }
        return nearestSegment(from: minutely, now: now, lookAheadEnd: lookAheadEnd)
    }

    private func buildURL(
        latitude: Double,
        longitude: Double,
        forecastIntervals: Int,
        pastIntervals: Int
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "minutely_15", value: "precipitation,rain,showers,weather_code"),
            URLQueryItem(name: "forecast_minutely_15", value: String(forecastIntervals)),
            URLQueryItem(name: "past_minutely_15", value: String(max(0, pastIntervals))),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "cell_selection", value: "nearest"),
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private func nearestSegment(from minutely: OpenMeteoRainWindow, now: Date, lookAheadEnd: Date) -> WeatherSegment? {
        let count = min(minutely.time.count, minutely.precipitation.count, minutely.rain.count)
        guard count > 0 else { return nil }

        let nowUnix = Int(now.timeIntervalSince1970)
        let currentIndex = currentIntervalIndex(forUnixTime: nowUnix, times: Array(minutely.time.prefix(count)))

        if minutely.effectiveRainAmount(at: currentIndex) > 0,
           let activeSegment = rainSegment(around: currentIndex, in: minutely, count: count) {
            return WeatherSegment(
                start: activeSegment.start,
                end: min(activeSegment.end, lookAheadEnd),
                peakPrecipitationAmount: activeSegment.peakPrecipitationAmount,
                dominantWeatherCode: activeSegment.dominantWeatherCode
            )
        }

        for index in 0 ..< count {
            guard minutely.effectiveRainAmount(at: index) > 0 else { continue }
            let eventDate = Date(timeIntervalSince1970: TimeInterval(minutely.time[index]))
            guard eventDate >= now, eventDate <= lookAheadEnd else { continue }
            guard let segment = rainSegment(around: index, in: minutely, count: count) else { continue }
            return WeatherSegment(
                start: segment.start,
                end: min(segment.end, lookAheadEnd),
                peakPrecipitationAmount: segment.peakPrecipitationAmount,
                dominantWeatherCode: segment.dominantWeatherCode
            )
        }

        return nil
    }

    private func currentIntervalIndex(forUnixTime nowUnix: Int, times: [Int]) -> Int {
        if let exact = times.lastIndex(where: { $0 <= nowUnix }) {
            return exact
        }
        return 0
    }

    private func rainSegment(around index: Int, in minutely: OpenMeteoRainWindow, count: Int) -> WeatherSegment? {
        guard minutely.effectiveRainAmount(at: index) > 0 else { return nil }

        var startIndex = index
        while startIndex > 0, minutely.effectiveRainAmount(at: startIndex - 1) > 0 {
            startIndex -= 1
        }

        var endIndex = index
        while endIndex + 1 < count, minutely.effectiveRainAmount(at: endIndex + 1) > 0 {
            endIndex += 1
        }

        let peakPrecipitationAmount = (startIndex ... endIndex)
            .map { minutely.effectiveRainAmount(at: $0) }
            .max() ?? minutely.effectiveRainAmount(at: index)
        let start = Date(timeIntervalSince1970: TimeInterval(minutely.time[startIndex]))
        let endUnix: Int
        if endIndex + 1 < count {
            endUnix = minutely.time[endIndex + 1]
        } else {
            endUnix = minutely.time[endIndex] + (15 * 60)
        }
        let end = Date(timeIntervalSince1970: TimeInterval(endUnix))
        return WeatherSegment(
            start: start,
            end: end,
            peakPrecipitationAmount: peakPrecipitationAmount,
            dominantWeatherCode: dominantWeatherCode(in: minutely, startIndex: startIndex, endIndex: endIndex)
        )
    }

    private func dominantWeatherCode(
        in minutely: OpenMeteoRainWindow,
        startIndex: Int,
        endIndex: Int
    ) -> Int? {
        (startIndex ... endIndex)
            .compactMap { minutely.weatherCodeValue(at: $0) }
            .max { WeatherObservationClassifier.priority(for: $0) < WeatherObservationClassifier.priority(for: $1) }
    }
}
