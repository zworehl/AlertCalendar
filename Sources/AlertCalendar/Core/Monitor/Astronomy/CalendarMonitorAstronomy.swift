import AppKit
import Foundation

extension CalendarMonitor {
    typealias AstronomyPhasePreview = (moment: AstronomyMoment, date: Date)

    private static let lunarSynodicMonthSeconds: TimeInterval = 29.530588853 * 86_400
    private static let earthAnomalisticYearSeconds: TimeInterval = 365.259636 * 86_400
    private static let lunarPhaseOffsets: [(moment: AstronomyMoment, cycleOffset: Double)] = [
        (.newMoon, 0.0 / 8.0),
        (.waxingCrescent, 1.0 / 8.0),
        (.firstQuarter, 2.0 / 8.0),
        (.waxingGibbous, 3.0 / 8.0),
        (.fullMoon, 4.0 / 8.0),
        (.waningGibbous, 5.0 / 8.0),
        (.lastQuarter, 6.0 / 8.0),
        (.waningCrescent, 7.0 / 8.0),
    ]
    private static let orbitalExtremaOffsets: [(moment: AstronomyMoment, cycleOffset: Double)] = [
        (.perihelion, 0.0),
        (.aphelion, 0.5),
    ]
    private static let tropicalYearSeconds: TimeInterval = 365.242189 * 86_400
    private static let lunarReferenceNewMoon: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2000
        components.month = 1
        components.day = 6
        components.hour = 18
        components.minute = 14
        components.second = 0
        return components.date ?? Date(timeIntervalSince1970: 947_182_440)
    }()
    private static let perihelionReferenceDate: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 1
        components.day = 3
        components.hour = 17
        components.minute = 15
        components.second = 0
        return components.date ?? Date(timeIntervalSince1970: 1_767_761_700)
    }()

    func loadAstronomyItems(from start: Date, to end: Date, settings: AppSettings) -> [UpcomingItem] {
        guard settings.includesAnyAstronomy else { return [] }

        let color = CalendarColorPalette.color(for: settings.astronomyColorID)
        var upcomingItems: [UpcomingItem] = []

        if settings.includeMoonPhases {
            upcomingItems.append(contentsOf: lunarPhaseEvents(from: start, to: end, color: color))
        }
        if settings.includeOrbitalHighlights {
            upcomingItems.append(contentsOf: orbitalHighlightEvents(from: start, to: end, color: color))
        }

        guard (-90 ... 90).contains(settings.astronomyLatitude),
              (-180 ... 180).contains(settings.astronomyLongitude) else {
            return upcomingItems.sorted { $0.date < $1.date }
        }

        let coordinate = (lat: settings.astronomyLatitude, lon: settings.astronomyLongitude)
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
                guard settings.includes(moment: moment) else { continue }
                if let existing = nextMoments[moment], existing.date <= event.date {
                    continue
                }
                nextMoments[moment] = event
            }
        }

        upcomingItems.append(contentsOf: AstronomyMoment.solarMoments.compactMap { nextMoments[$0] })
        return upcomingItems.sorted { $0.date < $1.date }
    }

    func astronomyEvents(for date: Date, coordinate: (lat: Double, lon: Double), color: AlertCalendarColor) -> [UpcomingItem] {
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

    func makeAstronomyItem(moment: AstronomyMoment, date: Date, color: AlertCalendarColor) -> UpcomingItem {
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
            organizer: nil,
            attendees: [],
            calendarID: nil,
            calendarName: "Astronomy",
            calendarColor: color,
            kind: .event,
            footballMatch: nil,
            footballMenuBarDisplay: nil
        )
    }

    func nextLunarPhaseMoments(from start: Date) -> [AstronomyPhasePreview] {
        Self.lunarPhaseOffsets.compactMap { definition in
            nextAstronomyOccurrence(
                from: start,
                referenceDate: Self.lunarReferenceNewMoon,
                cycleSeconds: Self.lunarSynodicMonthSeconds,
                cycleOffset: definition.cycleOffset
            ).map { (moment: definition.moment, date: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    func nextOrbitalHighlights(from start: Date) -> [AstronomyPhasePreview] {
        let orbitalExtrema = Self.orbitalExtremaOffsets.compactMap { definition in
            nextAstronomyOccurrence(
                from: start,
                referenceDate: Self.perihelionReferenceDate,
                cycleSeconds: Self.earthAnomalisticYearSeconds,
                cycleOffset: definition.cycleOffset
            ).map { (moment: definition.moment, date: $0) }
        }
        let seasonalHighlights = AstronomyMoment.seasonalMoments.compactMap { moment in
            nextSeasonalOccurrence(for: moment, from: start).map { (moment: moment, date: $0) }
        }

        return (orbitalExtrema + seasonalHighlights)
            .sorted { $0.date < $1.date }
    }

    private func lunarPhaseEvents(from start: Date, to end: Date, color: AlertCalendarColor) -> [UpcomingItem] {
        nextLunarPhaseMoments(from: start)
            .filter { $0.date >= start && $0.date <= end }
            .map { makeAstronomyItem(moment: $0.moment, date: $0.date, color: color) }
    }

    private func orbitalHighlightEvents(from start: Date, to end: Date, color: AlertCalendarColor) -> [UpcomingItem] {
        nextOrbitalHighlights(from: start)
            .filter { $0.date >= start && $0.date <= end }
            .map { makeAstronomyItem(moment: $0.moment, date: $0.date, color: color) }
    }

    private func nextSeasonalOccurrence(for moment: AstronomyMoment, from start: Date) -> Date? {
        guard AstronomyMoment.seasonalMoments.contains(moment) else { return nil }
        let startYear = Calendar(identifier: .gregorian).component(.year, from: start)

        for year in startYear ... (startYear + 2) {
            guard let occurrence = seasonalMomentDate(for: moment, year: year) else { continue }
            if occurrence > start {
                return occurrence
            }
        }

        return nil
    }

    private func seasonalMomentDate(for moment: AstronomyMoment, year: Int) -> Date? {
        let yearOffset = (Double(year) - 2000.0) / 1000.0
        let julianDay: Double

        switch moment {
        case .marchEquinox:
            julianDay = 2_451_623.80984
                + (365_242.37404 * yearOffset)
                + (0.05169 * pow(yearOffset, 2))
                - (0.00411 * pow(yearOffset, 3))
                - (0.00057 * pow(yearOffset, 4))
        case .juneSolstice:
            julianDay = 2_451_716.56767
                + (365_241.62603 * yearOffset)
                + (0.00325 * pow(yearOffset, 2))
                + (0.00888 * pow(yearOffset, 3))
                - (0.00030 * pow(yearOffset, 4))
        case .septemberEquinox:
            julianDay = 2_451_810.21715
                + (365_242.01767 * yearOffset)
                - (0.11575 * pow(yearOffset, 2))
                + (0.00337 * pow(yearOffset, 3))
                + (0.00078 * pow(yearOffset, 4))
        case .decemberSolstice:
            julianDay = 2_451_900.05952
                + (365_242.74049 * yearOffset)
                - (0.06223 * pow(yearOffset, 2))
                - (0.00823 * pow(yearOffset, 3))
                + (0.00032 * pow(yearOffset, 4))
        case .sunrise, .solarNoon, .sunset, .solarMidnight, .perihelion, .aphelion, .newMoon, .waxingCrescent, .firstQuarter, .waxingGibbous, .fullMoon, .waningGibbous, .lastQuarter, .waningCrescent:
            return nil
        }

        return dateFromJulianDay(julianDay)
    }

    private func nextAstronomyOccurrence(
        from start: Date,
        referenceDate: Date,
        cycleSeconds: TimeInterval,
        cycleOffset: Double
    ) -> Date? {
        guard cycleSeconds > 0 else { return nil }

        let elapsedCycles = start.timeIntervalSince(referenceDate) / cycleSeconds
        let cycleIndex = ceil(elapsedCycles - cycleOffset)
        var occurrence = referenceDate.addingTimeInterval((cycleIndex + cycleOffset) * cycleSeconds)

        if occurrence <= start {
            occurrence = occurrence.addingTimeInterval(cycleSeconds)
        }

        return occurrence
    }

    private func dateFromJulianDay(_ julianDay: Double) -> Date {
        Date(timeIntervalSince1970: (julianDay - 2_440_587.5) * 86_400)
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
