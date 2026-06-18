import XCTest
@testable import AlertCalendar

final class FootballFederationLogoResolverTests: XCTestCase {
    func testNationalTeamUsesFIFAAssociationLogo() {
        XCTAssertEqual(
            FootballFederationLogoResolver.federationLogoURL(
                name: "United States",
                abbreviation: "USA",
                countryName: "United States",
                isNational: true
            )?.absoluteString,
            "https://api.fifa.com/api/v3/picture/associations-sq-2/USA"
        )
    }

    func testKnownESPNCodeAliasesResolveToFIFAAssociationCodes() {
        XCTAssertEqual(FootballFederationLogoResolver.normalizedAssociationCode(from: "BKA"), "BFA")
        XCTAssertEqual(FootballFederationLogoResolver.normalizedAssociationCode(from: "MGL"), "MNG")
        XCTAssertEqual(FootballFederationLogoResolver.normalizedAssociationCode(from: "BVI"), "VGB")
        XCTAssertEqual(FootballFederationLogoResolver.normalizedAssociationCode(from: "CHE"), "SUI")
        XCTAssertEqual(FootballFederationLogoResolver.normalizedAssociationCode(from: "Switzerland"), "SUI")
        XCTAssertEqual(FootballFederationLogoResolver.normalizedAssociationCode(from: "USVI"), "VIR")
        XCTAssertEqual(FootballFederationLogoResolver.normalizedAssociationCode(from: "PSE"), "PLE")
    }

    func testUnsupportedNonFIFAAssociationsKeepExistingLogoURL() throws {
        let existingURL = try XCTUnwrap(URL(string: "https://a.espncdn.com/i/teamlogos/countries/500/mtq.png"))

        let resolvedURL = FootballFederationLogoResolver.resolvedLogoURL(
            existingLogoURL: existingURL,
            name: "Martinique",
            abbreviation: "MTQ",
            countryName: "Martinique",
            isNational: true
        )

        XCTAssertEqual(resolvedURL, existingURL)
    }

    func testGuadeloupeKeepsExistingLogoURL() throws {
        let existingURL = try XCTUnwrap(URL(string: "https://a.espncdn.com/i/teamlogos/countries/500/gdl.png"))

        let resolvedURL = FootballFederationLogoResolver.resolvedLogoURL(
            existingLogoURL: existingURL,
            name: "Guadeloupe",
            abbreviation: "GDL",
            countryName: "Guadeloupe",
            isNational: true
        )

        XCTAssertEqual(resolvedURL, existingURL)
    }

    func testPlaceholderCodesWithNumbersAreIgnored() {
        XCTAssertNil(FootballFederationLogoResolver.normalizedAssociationCode(from: "QW4"))
        XCTAssertNil(FootballFederationLogoResolver.normalizedAssociationCode(from: "RD16W5"))
        XCTAssertNil(FootballFederationLogoResolver.normalizedAssociationCode(from: "1A"))
    }

    func testClubTeamKeepsExistingLogoURL() throws {
        let existingURL = try XCTUnwrap(URL(string: "https://example.com/club.png"))

        let resolvedURL = FootballFederationLogoResolver.resolvedLogoURL(
            existingLogoURL: existingURL,
            name: "Barcelona",
            abbreviation: "BAR",
            countryName: "Spain",
            isNational: false
        )

        XCTAssertEqual(resolvedURL, existingURL)
    }

    func testResolvedNationalTeamDetailsReplaceCachedFlagWithFederationLogo() throws {
        let cachedFlagURL = try XCTUnwrap(URL(string: "https://a.espncdn.com/i/teamlogos/countries/500/esp.png"))
        let team = FootballTeamSummary(
            id: "2650",
            name: "Spain",
            abbreviation: "ESP",
            logoURL: nil,
            countryName: nil,
            isNational: false
        )

        let resolvedTeam = team.withResolvedDetails(
            countryName: "Spain",
            isNational: true,
            logoURL: cachedFlagURL
        )

        XCTAssertEqual(
            resolvedTeam.logoURL?.absoluteString,
            "https://api.fifa.com/api/v3/picture/associations-sq-2/ESP"
        )
    }
}
