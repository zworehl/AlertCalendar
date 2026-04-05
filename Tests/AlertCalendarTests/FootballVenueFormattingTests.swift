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

    func testVenueLocationTextIncludesStateWhenAvailable() {
        let json: [String: Any] = [
            "venue": [
                "fullName": "Mercedes-Benz Stadium",
                "address": [
                    "city": "Atlanta",
                    "state": "Georgia",
                    "country": "USA",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertEqual(value, "Mercedes-Benz Stadium, Atlanta, Georgia, USA")
    }

    func testVenueLocationTextReturnsNilWhenVenueIsStillTBD() {
        let json: [String: Any] = [
            "venue": [
                "fullName": "Venue TBD",
                "address": [
                    "city": "Miami",
                    "country": "United States",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertNil(value)
    }

    func testVenueLocationTextDropsPlaceholderAddressPieces() {
        let json: [String: Any] = [
            "venue": [
                "fullName": "MetLife Stadium",
                "address": [
                    "city": "TBD",
                    "country": "United States",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertEqual(value, "MetLife Stadium, United States")
    }
}
