import XCTest
@testable import AlertCalendar

final class FootballNationalLogoResolverTests: XCTestCase {
    func testNationalTeamUsesESPNCountryFlagFallback() {
        XCTAssertEqual(
            FootballNationalLogoResolver.nationalFlagLogoURL(
                name: "United States",
                abbreviation: "USA",
                countryName: "United States"
            )?.absoluteString,
            "https://a.espncdn.com/i/teamlogos/countries/500/usa.png"
        )
    }

    func testGeneratedLocalFlagImageURLUsesBundledAssetWhenAvailable() throws {
        let localURL = try XCTUnwrap(FootballNationalLogoResolver.localFlagImageURL(
            name: "Uruguay",
            abbreviation: "URU",
            countryName: "Uruguay"
        ))

        XCTAssertTrue(localURL.path.hasSuffix("/football-flag-uru.png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: localURL.path))
    }

    func testGeneratedLocalFlagImageURLUsesBundledAssetForTerritoryWhenAvailable() throws {
        let localURL = try XCTUnwrap(FootballNationalLogoResolver.localFlagImageURL(
            name: "Martinique",
            abbreviation: "MTQ",
            countryName: "Martinique"
        ))

        XCTAssertTrue(localURL.path.hasSuffix("/football-flag-mtq.png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: localURL.path))
    }

    func testGeneratedLocalFlagImageURLFallsBackWhenBundledAssetIsUnavailable() {
        XCTAssertNil(FootballNationalLogoResolver.localFlagImageURL(
            name: "Unknown",
            abbreviation: "ZZZ",
            countryName: "Unknown"
        ))
        XCTAssertEqual(
            FootballNationalLogoResolver.nationalFlagLogoURL(
                name: "Unknown",
                abbreviation: "ZZZ",
                countryName: "Unknown"
            )?.absoluteString,
            "https://a.espncdn.com/i/teamlogos/countries/500/zzz.png"
        )
    }

    func testKnownESPNCodeAliasesResolveToCountryCodes() {
        XCTAssertEqual(FootballNationalLogoResolver.normalizedAssociationCode(from: "BKA"), "BFA")
        XCTAssertEqual(FootballNationalLogoResolver.normalizedAssociationCode(from: "MGL"), "MNG")
        XCTAssertEqual(FootballNationalLogoResolver.normalizedAssociationCode(from: "BVI"), "VGB")
        XCTAssertEqual(FootballNationalLogoResolver.normalizedAssociationCode(from: "CHE"), "SUI")
        XCTAssertEqual(FootballNationalLogoResolver.normalizedAssociationCode(from: "Switzerland"), "SUI")
        XCTAssertEqual(FootballNationalLogoResolver.normalizedAssociationCode(from: "USVI"), "VIR")
        XCTAssertEqual(FootballNationalLogoResolver.normalizedAssociationCode(from: "PSE"), "PLE")
    }

    func testNationalTeamKeepsExistingCountryFlagURL() throws {
        let existingURL = try XCTUnwrap(URL(string: "https://a.espncdn.com/i/teamlogos/countries/500/mtq.png"))

        let resolvedURL = FootballNationalLogoResolver.resolvedLogoURL(
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

        let resolvedURL = FootballNationalLogoResolver.resolvedLogoURL(
            existingLogoURL: existingURL,
            name: "Guadeloupe",
            abbreviation: "GDL",
            countryName: "Guadeloupe",
            isNational: true
        )

        XCTAssertEqual(resolvedURL, existingURL)
    }

    func testPlaceholderCodesWithNumbersAreIgnored() {
        XCTAssertNil(FootballNationalLogoResolver.normalizedAssociationCode(from: "QW4"))
        XCTAssertNil(FootballNationalLogoResolver.normalizedAssociationCode(from: "RD16W5"))
        XCTAssertNil(FootballNationalLogoResolver.normalizedAssociationCode(from: "1A"))
    }

    func testClubTeamKeepsExistingLogoURL() throws {
        let existingURL = try XCTUnwrap(URL(string: "https://example.com/club.png"))

        let resolvedURL = FootballNationalLogoResolver.resolvedLogoURL(
            existingLogoURL: existingURL,
            name: "Barcelona",
            abbreviation: "BAR",
            countryName: "Spain",
            isNational: false
        )

        XCTAssertEqual(resolvedURL, existingURL)
    }

    func testResolvedNationalTeamDetailsKeepCachedFlagURL() throws {
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
            "https://a.espncdn.com/i/teamlogos/countries/500/esp.png"
        )
    }

    func testResolvedNationalTeamDetailsReplaceCachedFIFAAssociationLogoWithFlagURL() throws {
        let cachedAssociationURL = try XCTUnwrap(URL(string: "https://api.fifa.com/api/v3/picture/associations-sq-2/ESP"))
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
            logoURL: cachedAssociationURL
        )

        XCTAssertEqual(
            resolvedTeam.logoURL?.absoluteString,
            "https://a.espncdn.com/i/teamlogos/countries/500/esp.png"
        )
    }
}
