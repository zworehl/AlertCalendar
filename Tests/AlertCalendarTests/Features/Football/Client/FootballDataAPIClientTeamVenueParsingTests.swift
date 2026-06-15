import Foundation
import XCTest
@testable import AlertCalendar

final class FootballDataAPIClientTeamVenueParsingTests: FootballDataAPIClientTestCase {
    func testResolvedTeamCountryNameFallsBackToDomesticLeagueWhenClubLocationIsJustTheTeamName() {
        let root: [String: Any] = [
            "displayName": "Arsenal",
            "abbreviation": "ARS",
            "location": "Arsenal",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/venues/4228?lang=en&region=us",
                "address": [
                    "city": "Dublin",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "England")
    }
    func testResolvedTeamCountryNamePrefersNationalTeamNameOverVenueCountry() {
        let root: [String: Any] = [
            "displayName": "IR Iran",
            "abbreviation": "IRN",
            "location": "IR Iran",
            "isNational": true,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/fifa.world/venues/7614?lang=en&region=us",
                "address": [
                    "city": "Antalya",
                    "country": "Türkiye",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "IR Iran")
    }
    func testResolvedTeamCountryNameInfersNationalTeamWhenESPNMislabelsCountrySideAsClub() {
        let root: [String: Any] = [
            "displayName": "Curacao",
            "abbreviation": "CUR",
            "location": "Curacao",
            "isNational": false,
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "Curacao")
    }
    func testResolvedTeamVenueLocationTextKeepsVenueForInferredNationalTeam() {
        let root: [String: Any] = [
            "displayName": "Curacao",
            "abbreviation": "CUR",
            "location": "Curacao",
            "isNational": false,
            "venue": [
                "fullName": "NRG Stadium",
                "address": [
                    "city": "Houston",
                    "state": "Texas",
                    "country": "USA",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamVenueLocationText(from: root), "NRG Stadium, Houston, Texas, USA")
    }
    func testResolvedTeamCountryNamePrefersVenueCountryForClubs() {
        let root: [String: Any] = [
            "displayName": "Sporting CP",
            "abbreviation": "SCP",
            "location": "Sporting CP",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/por.1/venues/2352?lang=en&region=us",
                "address": [
                    "city": "Lisbon",
                    "country": "Portugal",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "Portugal")
    }
    func testResolvedTeamCountryNameIgnoresTouringVenueCountryForClubs() {
        let root: [String: Any] = [
            "displayName": "Liverpool",
            "abbreviation": "LIV",
            "location": "Liverpool",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/venues/1452?lang=en&region=us",
                "fullName": "Soldier Field",
                "address": [
                    "city": "Chicago",
                    "state": "Illinois",
                    "country": "USA",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "England")
    }
    func testResolvedTeamCountryNameKeepsCanadianMLSClubCountry() {
        let root: [String: Any] = [
            "displayName": "Toronto FC",
            "abbreviation": "TOR",
            "location": "Toronto FC",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/usa.1/venues/1845?lang=en&region=us",
                "fullName": "BMO Field",
                "address": [
                    "city": "Toronto",
                    "country": "Canada",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "Canada")
    }
    func testResolvedTeamCountryNameKeepsAccentInsensitiveCanadianClubCountry() {
        let root: [String: Any] = [
            "displayName": "CF Montréal",
            "abbreviation": "MTL",
            "location": "CF Montréal",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/usa.1/venues/1830?lang=en&region=us",
                "fullName": "Stade Saputo",
                "address": [
                    "city": "Montreal",
                    "country": "Canada",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "Canada")
    }
    func testResolvedTeamVenueLocationTextRejectsTouringClubVenueOutsideDomesticCountry() {
        let root: [String: Any] = [
            "displayName": "Liverpool",
            "abbreviation": "LIV",
            "location": "Liverpool",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/venues/1452?lang=en&region=us",
                "fullName": "Soldier Field",
                "address": [
                    "city": "Chicago",
                    "state": "Illinois",
                    "country": "USA",
                ],
            ],
        ]

        XCTAssertNil(FootballDataAPIClient.resolvedTeamVenueLocationText(from: root))
    }
    func testResolvedTeamVenueLocationTextRejectsForeignVenueWithoutClubLocalitySignals() {
        let root: [String: Any] = [
            "displayName": "Leeds United",
            "abbreviation": "LEE",
            "location": "Leeds United",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/venues/11120?lang=en&region=us",
                "fullName": "Croke Park",
                "address": [
                    "country": "Republic of Ireland",
                ],
            ],
        ]

        XCTAssertNil(FootballDataAPIClient.resolvedTeamVenueLocationText(from: root))
    }
    func testResolvedTeamVenueLocationTextKeepsCanadianMLSClubStadium() {
        let root: [String: Any] = [
            "displayName": "Toronto FC",
            "abbreviation": "TOR",
            "location": "Toronto FC",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/usa.1/venues/1845?lang=en&region=us",
                "fullName": "BMO Field",
                "address": [
                    "city": "Toronto",
                    "country": "Canada",
                ],
            ],
        ]

        XCTAssertEqual(FootballDataAPIClient.resolvedTeamVenueLocationText(from: root), "BMO Field, Toronto, Canada")
    }
    func testResolvedTeamVenueLocationTextKeepsConsistentHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Real Madrid",
            "abbreviation": "RMA",
            "location": "Real Madrid",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/esp.1/venues/10630?lang=en&region=us",
                "fullName": "Santiago Bernabéu",
                "address": [
                    "city": "Madrid",
                    "country": "Spain",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Santiago Bernabéu, Madrid, Spain"
        )
    }
    func testResolvedTeamVenueLocationTextKeepsJuventusHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Juventus",
            "abbreviation": "JUV",
            "location": "Juventus",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/ita.1/venues/4600?lang=en&region=us",
                "fullName": "Allianz Stadium",
                "address": [
                    "city": "Torino",
                    "country": "Italy",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Allianz Stadium, Torino, Italy"
        )
    }
    func testResolvedTeamVenueLocationTextKeepsAmericaHomeStadium() {
        let root: [String: Any] = [
            "displayName": "América",
            "abbreviation": "AME",
            "location": "América",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/mex.1/venues/218?lang=en&region=us",
                "fullName": "Estadio Banorte",
                "address": [
                    "city": "Mexico City",
                    "country": "Mexico",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Estadio Banorte, Mexico City, Mexico"
        )
    }
    func testResolvedTeamVenueLocationTextKeepsGuadalajaraHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Guadalajara",
            "abbreviation": "GDL",
            "location": "Guadalajara",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/mex.1/venues/197?lang=en&region=us",
                "fullName": "Estadio Akron",
                "address": [
                    "city": "Guadalajara",
                    "country": "Mexico",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Estadio Akron, Guadalajara, Mexico"
        )
    }
    func testResolvedTeamVenueLocationTextKeepsMonterreyHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Monterrey",
            "abbreviation": "MTY",
            "location": "Monterrey",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/mex.1/venues/7540?lang=en&region=us",
                "fullName": "Estadio BBVA",
                "address": [
                    "city": "Guadalupe",
                    "country": "Mexico",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Estadio BBVA, Monterrey, Mexico"
        )
    }
    func testResolvedTeamVenueLocationTextKeepsPumasHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Pumas UNAM",
            "abbreviation": "PUM",
            "location": "Pumas UNAM",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/mex.1/venues/234?lang=en&region=us",
                "fullName": "Estadio Olímpico Universitario",
                "address": [
                    "city": "Mexico City",
                    "country": "Mexico",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Estadio Olímpico Universitario, Mexico City, Mexico"
        )
    }
    func testResolvedTeamVenueLocationTextKeepsTigresHomeStadium() {
        let root: [String: Any] = [
            "displayName": "Tigres UANL",
            "abbreviation": "TIG",
            "location": "Tigres UANL",
            "isNational": false,
            "venue": [
                "$ref": "http://sports.core.api.espn.com/v2/sports/soccer/leagues/mex.1/venues/240?lang=en&region=us",
                "fullName": "Estadio Universitario",
                "address": [
                    "city": "San Nicolás de los Garza",
                    "country": "Mexico",
                ],
            ],
        ]

        XCTAssertEqual(
            FootballDataAPIClient.resolvedTeamVenueLocationText(from: root),
            "Estadio Universitario, San Nicolás de los Garza, Mexico"
        )
    }
    func testSummaryVenueLocationTextFallsBackToGameInfoVenueWhenHeaderVenueIsMissing() {
        let root: [String: Any] = [
            "gameInfo": [
                "venue": [
                    "fullName": "Alberto Jose Armando (La Bombonera)",
                    "address": [
                        "city": "Buenos Aires",
                        "country": "Argentina",
                    ],
                ],
            ],
        ]
        let competition: [String: Any] = [:]

        let value = FootballDataAPIClient.summaryVenueLocationText(from: root, competition: competition)

        XCTAssertEqual(value, "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina")
    }
    func testBestAvailableLocationTextPrefersMoreSpecificVenue() {
        let value = FootballDataAPIClient.bestAvailableLocationText(
            reportedLocationText: "Buenos Aires, Argentina",
            fallbackLocationText: "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina"
        )

        XCTAssertEqual(value, "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina")
    }
    func testBestAvailableLocationTextReplacesPlaceholderVenue() {
        let value = FootballDataAPIClient.bestAvailableLocationText(
            reportedLocationText: "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina",
            fallbackLocationText: "TBC"
        )

        XCTAssertEqual(value, "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina")
    }
    func testBestAvailableLocationTextReturnsNilWhenOnlyPlaceholderVenueExists() {
        let value = FootballDataAPIClient.bestAvailableLocationText(
            reportedLocationText: "Venue TBD",
            fallbackLocationText: nil
        )

        XCTAssertNil(value)
    }}
