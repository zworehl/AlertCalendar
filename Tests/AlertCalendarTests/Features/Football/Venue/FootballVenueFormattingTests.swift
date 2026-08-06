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

    func testVenueLocationTextCanonicalizesKnownAmbiguousVenueID() {
        let json: [String: Any] = [
            "venue": [
                "id": "6351",
                "fullName": "Estadio BBVA",
                "address": [
                    "city": "Guadalupe",
                    "country": "Mexico",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertEqual(value, "Estadio BBVA, Monterrey, Mexico")
    }

    func testVenueLocationTextCanonicalizesKnownAmbiguousVenueNameAndContext() {
        let json: [String: Any] = [
            "venue": [
                "fullName": "Estadio BBVA",
                "address": [
                    "city": "Guadalupe",
                    "country": "Mexico",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertEqual(value, "Estadio BBVA, Monterrey, Mexico")
    }

    func testVenueLocationTextCanonicalizesWorldCupVenueID() {
        let json: [String: Any] = [
            "venue": [
                "id": "1672",
                "fullName": "Estadio Azteca",
                "address": [
                    "city": "Ciudad de México",
                    "country": "México",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertEqual(value, "Estadio Banorte, Mexico City, Mexico")
    }

    func testVenueLocationTextCanonicalizesWorldCupVenueNameAndContextWithoutID() {
        let json: [String: Any] = [
            "venue": [
                "fullName": "GEHA Field at Arrowhead Stadium",
                "address": [
                    "city": "Kansas City, Missouri",
                    "country": "USA",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertEqual(value, "GEHA Field at Arrowhead Stadium, Kansas City, Missouri, USA")
    }

    func testVenueLocationTextCanonicalizesMalformedESPNVenueID() {
        let json: [String: Any] = [
            "venue": [
                "id": "7474",
                "fullName": "Toyota Stadium",
                "address": [
                    "city": "Toyota Stadium",
                    "country": "USA",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertEqual(value, "Toyota Stadium, Frisco, Texas, USA")
    }

    func testVenueLocationTextCanonicalizesRenamedVenueID() {
        let json: [String: Any] = [
            "venue": [
                "id": "8689",
                "fullName": "Lower.com Field",
                "address": [
                    "city": "Columbus, Ohio",
                    "country": "USA",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertEqual(value, "ScottsMiracle-Gro Field, Columbus, Ohio, USA")
    }

    func testVenueLocationTextSuppressesAmbiguousCountryOnlyVenueFallback() {
        let json: [String: Any] = [
            "venue": [
                "fullName": "Central Stadium",
                "address": [
                    "country": "USA",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertNil(value)
    }

    func testVenueLocationTextPreservesIdentifiedVenueWhenESPNRepeatsNameAsCity() {
        let json: [String: Any] = [
            "venue": [
                "id": "6194",
                "fullName": "Estadio Nacional de Fútbol",
                "address": [
                    "city": "Estadio Nacional de Fútbol",
                    "country": "Nicaragua",
                ],
            ],
        ]

        let value = FootballDataAPIClient.venueLocationText(from: json)

        XCTAssertEqual(value, "Estadio Nacional de Fútbol, Nicaragua")
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

        XCTAssertEqual(value, "MetLife Stadium, East Rutherford, New Jersey, USA")
    }
}
