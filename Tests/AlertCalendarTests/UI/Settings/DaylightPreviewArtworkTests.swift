import XCTest
@testable import AlertCalendar

final class DaylightPreviewArtworkTests: XCTestCase {
    func testTerminatorLongitudesAtEquinoxSitRoughlyNinetyDegreesFromSubsolarLongitude() {
        let solarState = DaylightSolarState(date: testDate("2026-03-20T12:00:00Z"))

        guard let terminator = DaylightPreviewArtwork.terminatorLongitudes(for: 0, solarState: solarState) else {
            return XCTFail("Expected an equatorial terminator on the equinox")
        }

        XCTAssertEqual(terminator.west, -90, accuracy: 6)
        XCTAssertEqual(terminator.east, 90, accuracy: 6)
    }

    func testSolarAltitudeVariesByLatitudeForSameLongitude() {
        let solarState = DaylightSolarState(date: testDate("2026-06-21T12:00:00Z"))

        let equatorialAltitude = DaylightPreviewArtwork.solarAltitudeDegrees(
            latitude: 0,
            longitude: solarState.subsolarLongitude,
            solarState: solarState
        )
        let northernAltitude = DaylightPreviewArtwork.solarAltitudeDegrees(
            latitude: 60,
            longitude: solarState.subsolarLongitude,
            solarState: solarState
        )
        let southernAltitude = DaylightPreviewArtwork.solarAltitudeDegrees(
            latitude: -60,
            longitude: solarState.subsolarLongitude,
            solarState: solarState
        )

        XCTAssertGreaterThan(equatorialAltitude, 60)
        XCTAssertLessThan(northernAltitude, equatorialAltitude)
        XCTAssertGreaterThan(northernAltitude, southernAltitude)
        XCTAssertLessThan(southernAltitude, 10)
    }

    func testTerminatorDisappearsForPolarDayAtSummerSolstice() {
        let solarState = DaylightSolarState(date: testDate("2026-06-21T12:00:00Z"))

        XCTAssertNil(
            DaylightPreviewArtwork.terminatorLongitudes(for: 78, solarState: solarState)
        )
    }

    private func testDate(_ rawValue: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: rawValue) else {
            XCTFail("Unable to parse test date \(rawValue)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }
}
