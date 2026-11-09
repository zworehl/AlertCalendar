import Foundation
import XCTest
@testable import AlertCalendar

final class FootballTeamBroadcastCodeTests: XCTestCase {
    private struct Audit: Decodable {
        let teams: [Team]
        struct Team: Decodable {
            let id: String
            let name: String
            let shortName: String
            let providerCode: String
            let expectedCode: String
            let isNational: Bool
            let competitions: [String]
        }
    }

    func testEveryReviewedTeamHasItsExpectedBroadcastCodeForFullAndShortNames() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "football-team-abbreviation-audit", withExtension: "json"))
        let audit = try JSONDecoder().decode(Audit.self, from: Data(contentsOf: url))
        XCTAssertEqual(audit.teams.count, 548)
        for row in audit.teams {
            for name in Set([row.name, row.shortName]) {
                let team = FootballTeamSummary(
                    id: row.id, name: name, abbreviation: row.providerCode, logoURL: nil,
                    countryName: row.isNational ? row.name : "Resolved club country", isNational: row.isNational
                )
                let code = FootballFixtureFormatter.teamDisplayIdentifier(for: team)
                XCTAssertEqual(code, row.expectedCode, "\(row.id): \(name)")
                XCTAssertTrue((1...3).contains(code.count), name)
                XCTAssertTrue(code.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }, name)
            }
        }
    }

    func testCompetitionCatalogHasNoAmbiguousTeamCodes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "football-team-abbreviation-audit", withExtension: "json"))
        let audit = try JSONDecoder().decode(Audit.self, from: Data(contentsOf: url))
        var teamsByCompetitionAndCode: [String: String] = [:]
        for row in audit.teams where !row.providerCode.hasPrefix("TBD") {
            let team = FootballTeamSummary(
                id: row.id, name: row.name, abbreviation: row.providerCode, logoURL: nil,
                countryName: row.isNational ? row.name : "Resolved club country", isNational: row.isNational
            )
            let code = FootballFixtureFormatter.teamDisplayIdentifier(for: team)
            for competition in row.competitions {
                let key = "\(competition)|\(code)"
                XCTAssertNil(teamsByCompetitionAndCode[key], "\(competition): \(code) identifies both \(row.name) and \(teamsByCompetitionAndCode[key] ?? "")")
                teamsByCompetitionAndCode[key] = row.name
            }
        }
    }

    func testSanCarlosClubsWithIdenticalShortNamesKeepDifferentCodes() {
        let adSanCarlos = FootballTestData.clubTeam(id: "859", name: "San Carlos", abbreviation: "ADSC", countryName: "Costa Rica")
        let interSanCarlos = FootballTestData.clubTeam(id: "131790", name: "San Carlos", abbreviation: "ISC", countryName: "Costa Rica")
        XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: adSanCarlos), "SCA")
        XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: interSanCarlos), "ISC")
    }

    func testMissingOrLongUnknownCodesStillProduceShortReadableIdentifiers() {
        for (name, expected) in [
            ("Paris Saint Germain", "PSG"), ("West Ham United", "WHU"),
            ("Deportivo Águila", "DAG"), ("FC Example", "EXA"), ("", "TBD")
        ] {
            XCTAssertEqual(FootballFixtureFormatter.normalizedAbbreviation("", fallbackName: name), expected)
        }
        XCTAssertEqual(FootballFixtureFormatter.normalizedAbbreviation("LONG-CODE", fallbackName: "Example"), "EXA")
    }

    func testCalendarAndMenuBarShareCodesAndRecoverPreviousProviderTitles() throws {
        let match = FootballTestData.match(
            id: "broadcast-match", statusState: .inProgress,
            homeTeam: FootballTestData.clubTeam(id: "360", name: "Manchester United", abbreviation: "MAN", countryName: "England"),
            awayTeam: FootballTestData.clubTeam(id: "132", name: "Bayern Munich", abbreviation: "MUN", countryName: "Germany")
        )
        let display = FootballFixtureFormatter.menuBarDisplay(
            for: match, competitionLocalLogoURL: nil, homeLocalLogoURL: nil, awayLocalLogoURL: nil
        )
        XCTAssertEqual(display.homeAbbreviation, "MUN")
        XCTAssertEqual(display.awayAbbreviation, "BAY")
        XCTAssertTrue(FootballFixtureFormatter.calendarTitle(for: match).hasPrefix("MUN "))
        XCTAssertTrue(FootballFixtureFormatter.calendarTitle(for: match).hasSuffix(" BAY"))
        let oldKey = try XCTUnwrap(FootballFixtureFormatter.calendarIdentityKey(fromCalendarTitle: "MAN 🇬🇧 - 🇩🇪 MUN"))
        XCTAssertTrue(FootballFixtureFormatter.calendarIdentityKeys(for: match).contains(oldKey))
    }

    func testSharedProviderNamesRequireTheCorrectTeamIdentity() {
        for name in ["Alianza FC", "Alianza"] {
            let panama = FootballTestData.clubTeam(id: "21520", name: name, abbreviation: "ALI", countryName: "Panama")
            let salvador = FootballTestData.clubTeam(id: "7225", name: name, abbreviation: "ALI", countryName: "El Salvador")
            let colombia = FootballTestData.clubTeam(id: "9761", name: name, abbreviation: "AFC", countryName: "Colombia")
            XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: panama), "AFC")
            XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: salvador), "ALI")
            XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: colombia), "AFC")
        }
        let mixco = FootballTestData.clubTeam(id: "20036", name: "Deportivo", abbreviation: "DEP", countryName: "Guatemala")
        let coruna = FootballTestData.clubTeam(id: "90", name: "Deportivo", abbreviation: "DEP", countryName: "Spain")
        XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: mixco), "MIX")
        XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: coruna), "DEP")
    }

    func testEuropaLeagueCeltaAndCelticUseDistinctCodes() {
        let celta = FootballTestData.clubTeam(id: "85", name: "Celta Vigo", abbreviation: "CEL", countryName: "Spain")
        let celtic = FootballTestData.clubTeam(id: "256", name: "Celtic", abbreviation: "CEL", countryName: "Scotland")
        let match = FootballTestData.match(id: "celta-celtic", statusState: .scheduled, homeTeam: celta, awayTeam: celtic)
        XCTAssertTrue(FootballFixtureFormatter.calendarTitle(for: match).hasPrefix("CLT "))
        XCTAssertTrue(FootballFixtureFormatter.calendarTitle(for: match).hasSuffix(" CEL"))
    }

    func testNewCodesRecoverPreviousCalendarTitlesEvenAfterProviderAdoptsNewCodes() throws {
        let changedIDs: Set<String> = [
            "2057", "7239", "862", "7237", "20705", "21520", "85", "124", "20036", "2671",
            "2919", "2790", "3385", "7120", "8625", "4888", "4319", "4388", "4384", "7657",
        ]
        let url = try XCTUnwrap(Bundle.module.url(forResource: "football-team-abbreviation-audit", withExtension: "json"))
        let audit = try JSONDecoder().decode(Audit.self, from: Data(contentsOf: url))
        for row in audit.teams where changedIDs.contains(row.id) {
            let updatedTeam = FootballTeamSummary(
                id: row.id, name: row.name, abbreviation: row.expectedCode, logoURL: nil,
                countryName: row.isNational ? row.name : "Resolved club country", isNational: row.isNational
            )
            let away = FootballTestData.clubTeam(id: "124", name: "Dortmund", abbreviation: "BVB", countryName: "Germany")
            let match = FootballTestData.match(id: row.id, statusState: .scheduled, homeTeam: updatedTeam, awayTeam: away)
            let keys = FootballFixtureFormatter.calendarIdentityKeys(for: match)
            XCTAssertTrue(keys.contains("\(row.providerCode)|DOR"), row.name)
            XCTAssertTrue(keys.contains("\(row.expectedCode)|DOR"), row.name)
            XCTAssertTrue(keys.contains("\(row.providerCode)|BVB"), row.name)
        }
    }

    func testReviewedIdentityDoesNotRenameAnUnrelatedClub() {
        let unrelated = FootballTestData.clubTeam(id: "859", name: "Other Club", abbreviation: "OTH", countryName: "Costa Rica")
        XCTAssertEqual(FootballFixtureFormatter.teamDisplayIdentifier(for: unrelated), "OTH")
    }
}
