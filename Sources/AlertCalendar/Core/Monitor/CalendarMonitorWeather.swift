import AppKit
import Foundation

extension CalendarMonitor {
    private static let rainObservationIntervals = 672

    func loadWeatherRainItem(now: Date, end: Date, settings: SettingsSnapshot) async -> UpcomingItem? {
        guard (-90 ... 90).contains(settings.astronomyLatitude),
              (-180 ... 180).contains(settings.astronomyLongitude) else {
            return nil
        }

        let observation = RainObservationService()

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
                title: weatherTitle(for: segment.peakRainAmount),
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
                kind: .weather
            )
        } catch {
            return nil
        }
    }

    func weatherTitle(for rainAmount: Double) -> String {
        if rainAmount >= 2.0 {
            return "Thunderstorm"
        }
        if rainAmount >= 0.5 {
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
    let rain: [Double]
}

private struct RainSegment {
    let start: Date
    let end: Date
    let peakRainAmount: Double
}

private struct RainObservationService {
    func fetchNearestRainSegment(
        now: Date,
        lookAheadEnd: Date,
        latitude: Double,
        longitude: Double,
        forecastIntervals: Int,
        pastIntervals: Int
    ) async throws -> RainSegment? {
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
            URLQueryItem(name: "minutely_15", value: "rain"),
            URLQueryItem(name: "forecast_minutely_15", value: String(forecastIntervals)),
            URLQueryItem(name: "past_minutely_15", value: String(max(0, pastIntervals))),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private func nearestSegment(from minutely: OpenMeteoRainWindow, now: Date, lookAheadEnd: Date) -> RainSegment? {
        let count = min(minutely.time.count, minutely.rain.count)
        guard count > 0 else { return nil }

        let nowUnix = Int(now.timeIntervalSince1970)
        let currentIndex = currentIntervalIndex(forUnixTime: nowUnix, times: minutely.time)

        if minutely.rain[currentIndex] > 0,
           let activeSegment = rainSegment(around: currentIndex, in: minutely, count: count) {
            return RainSegment(
                start: activeSegment.start,
                end: min(activeSegment.end, lookAheadEnd),
                peakRainAmount: activeSegment.peakRainAmount
            )
        }

        for index in 0 ..< count {
            guard minutely.rain[index] > 0 else { continue }
            let eventDate = Date(timeIntervalSince1970: TimeInterval(minutely.time[index]))
            guard eventDate >= now, eventDate <= lookAheadEnd else { continue }
            guard let segment = rainSegment(around: index, in: minutely, count: count) else { continue }
            return RainSegment(
                start: segment.start,
                end: min(segment.end, lookAheadEnd),
                peakRainAmount: segment.peakRainAmount
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

    private func rainSegment(around index: Int, in minutely: OpenMeteoRainWindow, count: Int) -> RainSegment? {
        guard minutely.rain[index] > 0 else { return nil }

        var startIndex = index
        while startIndex > 0, minutely.rain[startIndex - 1] > 0 {
            startIndex -= 1
        }

        var endIndex = index
        while endIndex + 1 < count, minutely.rain[endIndex + 1] > 0 {
            endIndex += 1
        }

        let peakRainAmount = minutely.rain[startIndex ... endIndex].max() ?? minutely.rain[index]
        let start = Date(timeIntervalSince1970: TimeInterval(minutely.time[startIndex]))
        let endUnix: Int
        if endIndex + 1 < count {
            endUnix = minutely.time[endIndex + 1]
        } else {
            endUnix = minutely.time[endIndex] + (15 * 60)
        }
        let end = Date(timeIntervalSince1970: TimeInterval(endUnix))
        return RainSegment(start: start, end: end, peakRainAmount: peakRainAmount)
    }
}
