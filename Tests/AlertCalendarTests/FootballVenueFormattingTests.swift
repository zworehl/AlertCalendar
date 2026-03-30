import XCTest
@testable import AlertCalendar

final class FootballVenueFormattingTests: XCTestCase {
    func testVenueLocationTextPreservesVenueCityAndCountry() {
        let json: [String: Any] = [
            "venue": [
                "fullName": "Estadio Olimpico de la UCV",
                "address": [
                    "city": "Caracas",
                    "country": "Venezuela",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertEqual(value, "Estadio Olimpico de la UCV, Caracas, Venezuela")
    }

    func testVenueLocationTextDeduplicatesRepeatedComponents() {
        let json: [String: Any] = [
            "venue": [
                "fullName": "Monumental",
                "address": [
                    "city": "Monumental",
                    "country": "Argentina",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertEqual(value, "Monumental, Argentina")
    }
}
