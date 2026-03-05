import AppKit
import Foundation

extension CalendarMonitor {
    func loadAstronomyItems(from start: Date, to end: Date, settings: SettingsSnapshot) -> [UpcomingItem] {
        guard (-90 ... 90).contains(settings.astronomyLatitude),
              (-180 ... 180).contains(settings.astronomyLongitude) else {
            return []
        }

        let coordinate = (lat: settings.astronomyLatitude, lon: settings.astronomyLongitude)
        let color = CalendarColorPalette.color(for: settings.astronomyColorID)
        var nextMoments: [AstronomyMoment: UpcomingItem] = [:]
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let dayCount = max(0, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0)

        for dayOffset in 0 ... dayCount {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startDay) else { continue }
            let events = astronomyEvents(for: day, coordinate: coordinate, color: color)

            for event in events where event.date >= start && event.date <= end {
                guard let moment = AstronomyMoment(eventTitle: event.title) else { continue }
                if let existing = nextMoments[moment], existing.date <= event.date {
                    continue
                }
                nextMoments[moment] = event
            }
        }

        return AstronomyMoment.allCases
            .compactMap { nextMoments[$0] }
            .sorted { $0.date < $1.date }
    }

    func astronomyEvents(for date: Date, coordinate: (lat: Double, lon: Double), color: NSColor) -> [UpcomingItem] {
        guard let solar = solarTimes(for: date, coordinate: coordinate, timeZone: .current) else { return [] }

        var items: [UpcomingItem] = []
        if let sunrise = solar.sunrise {
            items.append(makeAstronomyItem(moment: .sunrise, date: sunrise, color: color))
        }
        if let solarNoon = solar.solarNoon {
            items.append(makeAstronomyItem(moment: .solarNoon, date: solarNoon, color: color))
        }
        if let sunset = solar.sunset {
            items.append(makeAstronomyItem(moment: .sunset, date: sunset, color: color))
        }
        if let solarMidnight = solar.solarMidnight {
            items.append(makeAstronomyItem(moment: .solarMidnight, date: solarMidnight, color: color))
        }

        return items
    }

    func makeAstronomyItem(moment: AstronomyMoment, date: Date, color: NSColor) -> UpcomingItem {
        let slug = moment.rawValue.replacingOccurrences(of: " ", with: "-")
        let dayKey = Self.dayKeyFormatter.string(from: date)
        return UpcomingItem(
            id: "\(slug)-\(dayKey)",
            title: moment.title,
            date: date,
            endDate: nil,
            isAllDay: false,
            showsMutedBackground: false,
            travelTimeMinutes: nil,
            locationText: nil,
            meetingURL: nil,
            calendarID: nil,
            calendarName: "Astronomy",
            calendarColor: color,
            kind: .event
        )
    }

    func solarTimes(for date: Date, coordinate: (lat: Double, lon: Double), timeZone: TimeZone) -> (sunrise: Date?, solarNoon: Date?, sunset: Date?, solarMidnight: Date?)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let startOfDay = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: date)),
              let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date),
              let year = calendar.dateComponents([.year], from: date).year else {
            return nil
        }

        let sunriseHours = solarEventUTCHours(
            dayOfYear: Double(dayOfYear),
            latitude: coordinate.lat,
            longitude: coordinate.lon,
            zenith: 90.833,
            isSunrise: true
        )
        let sunsetHours = solarEventUTCHours(
            dayOfYear: Double(dayOfYear),
            latitude: coordinate.lat,
            longitude: coordinate.lon,
            zenith: 90.833,
            isSunrise: false
        )

        let sunrise = sunriseHours.flatMap { utcHours in
            dateFromUTCHours(
                utcHours: utcHours,
                year: year,
                month: calendar.component(.month, from: startOfDay),
                day: calendar.component(.day, from: startOfDay),
                timeZone: timeZone
            )
        }
        let sunset = sunsetHours.flatMap { utcHours in
            dateFromUTCHours(
                utcHours: utcHours,
                year: year,
                month: calendar.component(.month, from: startOfDay),
                day: calendar.component(.day, from: startOfDay),
                timeZone: timeZone
            )
        }

        let solarNoon: Date?
        if let sunrise, let sunset {
            solarNoon = sunrise.addingTimeInterval(sunset.timeIntervalSince(sunrise) / 2.0)
        } else {
            solarNoon = nil
        }
        let solarMidnight = solarNoon?.addingTimeInterval(12 * 3600)

        return (sunrise: sunrise, solarNoon: solarNoon, sunset: sunset, solarMidnight: solarMidnight)
    }

    func solarEventUTCHours(dayOfYear: Double, latitude: Double, longitude: Double, zenith: Double, isSunrise: Bool) -> Double? {
        let lngHour = longitude / 15.0
        let tBase = isSunrise ? 6.0 : 18.0
        let t = dayOfYear + ((tBase - lngHour) / 24.0)

        let m = (0.9856 * t) - 3.289
        var l = m + (1.916 * sin(deg2rad(m))) + (0.020 * sin(deg2rad(2 * m))) + 282.634
        l = normalizeDegrees(l)

        var ra = rad2deg(atan(0.91764 * tan(deg2rad(l))))
        ra = normalizeDegrees(ra)
        let lQuadrant = floor(l / 90.0) * 90.0
        let raQuadrant = floor(ra / 90.0) * 90.0
        ra = (ra + (lQuadrant - raQuadrant)) / 15.0

        let sinDec = 0.39782 * sin(deg2rad(l))
        let cosDec = cos(asin(sinDec))
        let cosH = (cos(deg2rad(zenith)) - (sinDec * sin(deg2rad(latitude)))) / (cosDec * cos(deg2rad(latitude)))

        if cosH > 1 || cosH < -1 {
            return nil
        }

        let h = isSunrise ? (360.0 - rad2deg(acos(cosH))) : rad2deg(acos(cosH))
        let hHours = h / 15.0
        let tLocal = hHours + ra - (0.06571 * t) - 6.622
        let ut = tLocal - lngHour
        return normalizeHours(ut)
    }

    func dateFromUTCHours(utcHours: Double, year: Int, month: Int, day: Int, timeZone: TimeZone) -> Date? {
        let totalSeconds = Int(round(utcHours * 3600))
        let hours = (totalSeconds / 3600) % 24
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hours
        components.minute = minutes
        components.second = seconds

        guard var utcDate = components.date else { return nil }

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone

        var expectedLocalComponents = DateComponents()
        expectedLocalComponents.calendar = localCalendar
        expectedLocalComponents.timeZone = timeZone
        expectedLocalComponents.year = year
        expectedLocalComponents.month = month
        expectedLocalComponents.day = day

        guard let expectedLocalDay = localCalendar.date(from: expectedLocalComponents) else {
            return utcDate
        }

        let actualLocalDayComponents = localCalendar.dateComponents([.year, .month, .day], from: utcDate)
        guard let actualLocalDay = localCalendar.date(from: actualLocalDayComponents) else {
            return utcDate
        }

        let delta = localCalendar.dateComponents([.day], from: actualLocalDay, to: expectedLocalDay).day ?? 0
        if delta != 0,
           let shifted = localCalendar.date(byAdding: .day, value: delta, to: utcDate) {
            utcDate = shifted
        }

        return utcDate
    }

    func deg2rad(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    func rad2deg(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }

    func normalizeDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360.0)
        if value < 0 { value += 360.0 }
        return value
    }

    func normalizeHours(_ hours: Double) -> Double {
        var value = hours.truncatingRemainder(dividingBy: 24.0)
        if value < 0 { value += 24.0 }
        return value
    }
}
