import CoreLocation
import CoreWLAN
import Foundation

extension CalendarMonitor {
    func refreshAstronomyCoordinatesFromSystem() {
        scheduleAutomaticAstronomyLocationRefresh(trigger: .manual)
    }

    func refreshAutomaticAstronomyLocationIfNeeded(trigger: AutomaticAstronomyLocationRefreshTrigger) async {
        await refreshAutomaticAstronomyLocationIfNeeded(trigger: trigger, referenceDate: fixedSecondNow())
    }

    func scheduleHourlyAutomaticAstronomyLocationRefreshIfNeeded(now: Date) {
        scheduleAutomaticAstronomyLocationRefresh(trigger: .hourly, referenceDate: now)
    }

    func scheduleAutomaticAstronomyLocationRefresh(
        trigger: AutomaticAstronomyLocationRefreshTrigger,
        referenceDate: Date = AlertCalendarClock.nowRoundedToSecond()
    ) {
        guard automaticAstronomyLocationRefreshTask == nil else { return }

        automaticAstronomyLocationRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { automaticAstronomyLocationRefreshTask = nil }
            await refreshAutomaticAstronomyLocationIfNeeded(trigger: trigger, referenceDate: referenceDate)
        }
    }

    func refreshAutomaticAstronomyLocationIfNeeded(
        trigger: AutomaticAstronomyLocationRefreshTrigger,
        referenceDate: Date
    ) async {
        guard defaults.bool(forKey: DefaultsKeys.useAutomaticAstronomyLocation) else {
            astronomyLocationStatus = "Manual coordinates"
            return
        }

        guard Self.shouldRefreshAutomaticAstronomyLocation(
            lastAttemptDate: lastAutomaticAstronomyLocationRefreshAttemptDate,
            now: referenceDate,
            trigger: trigger
        ) else {
            return
        }

        guard !isAutomaticAstronomyLocationRefreshRunning else { return }

        CalendarMonitorLog.location.debug("Refreshing automatic astronomy location: \(String(describing: trigger), privacy: .public)")
        lastAutomaticAstronomyLocationRefreshAttemptDate = referenceDate
        isAutomaticAstronomyLocationRefreshRunning = true
        defer { isAutomaticAstronomyLocationRefreshRunning = false }

        await updateAstronomyCoordinatesFromSystem()
    }

    nonisolated static func shouldRefreshAutomaticAstronomyLocation(
        lastAttemptDate: Date?,
        now: Date,
        trigger: AutomaticAstronomyLocationRefreshTrigger
    ) -> Bool {
        CalendarMonitorTime.hasElapsed(since: lastAttemptDate, now: now, interval: trigger.minimumInterval)
    }

    func updateAstronomyCoordinatesFromSystem() async {
        guard defaults.bool(forKey: DefaultsKeys.useAutomaticAstronomyLocation) else {
            astronomyLocationStatus = "Manual coordinates"
            return
        }

        guard CLLocationManager.locationServicesEnabled() else {
            astronomyLocationStatus = "Location Services are disabled."
            return
        }

        let status = await requestLocationAuthorizationIfNeeded()

        guard isLocationAuthorized(status) else {
            astronomyLocationStatus = "Enable Location permission for automatic coordinates."
            return
        }

        guard let detectedLocation = await requestBestAvailableAstronomyLocation() else {
            astronomyLocationStatus = fallbackAstronomyLocationStatus(
                prefix: "Could not refresh current location"
            )
            return
        }

        let coordinate = detectedLocation.coordinate
        let roundedLatitude = AppSettingsRules.roundedCoordinate(coordinate.latitude)
        let roundedLongitude = AppSettingsRules.roundedCoordinate(coordinate.longitude)
        defaults.set(roundedLatitude, forKey: DefaultsKeys.astronomyLatitude)
        defaults.set(roundedLongitude, forKey: DefaultsKeys.astronomyLongitude)
        markAstronomyLocationRefreshed(at: fixedSecondNow())
        astronomyLocationStatus = String(
            format: "\(detectedLocation.statusPrefix): %.2f, %.2f",
            roundedLatitude,
            roundedLongitude
        )
        await refreshUpcomingItems(reason: .locationChanged)
    }

    func detectAstronomyCoordinate() async -> CLLocationCoordinate2D? {
        guard CLLocationManager.locationServicesEnabled() else {
            astronomyLocationStatus = "Location Services are disabled."
            return nil
        }

        let status = await requestLocationAuthorizationIfNeeded()

        guard isLocationAuthorized(status) else {
            astronomyLocationStatus = "Enable Location permission for automatic coordinates."
            return nil
        }

        guard let detectedLocation = await requestBestAvailableAstronomyLocation() else {
            astronomyLocationStatus = fallbackAstronomyLocationStatus(
                prefix: "Could not detect current location"
            )
            return nil
        }

        let coordinate = detectedLocation.coordinate
        astronomyLocationStatus = String(
            format: "\(detectedLocation.detectedStatusPrefix): %.2f, %.2f",
            AppSettingsRules.roundedCoordinate(coordinate.latitude),
            AppSettingsRules.roundedCoordinate(coordinate.longitude)
        )
        return coordinate
    }

    func fallbackAstronomyLocationStatus(prefix: String) -> String {
        guard let latitude = defaults.object(forKey: DefaultsKeys.astronomyLatitude) as? Double,
              let longitude = defaults.object(forKey: DefaultsKeys.astronomyLongitude) as? Double else {
            return "\(prefix). Check Location Services and Wi-Fi, or enter coordinates manually."
        }

        guard (-90 ... 90).contains(latitude),
              (-180 ... 180).contains(longitude) else {
            return "\(prefix). Check Location Services and Wi-Fi, or enter coordinates manually."
        }

        return String(
            format: "\(prefix). Using saved coordinates: %.2f, %.2f",
            AppSettingsRules.roundedCoordinate(latitude),
            AppSettingsRules.roundedCoordinate(longitude)
        )
    }
}
