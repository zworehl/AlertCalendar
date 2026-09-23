import Foundation
import XCTest
@testable import AlertCalendar

final class FootballTeamCountryRecoveryTests: FootballDataAPIClientTestCase {
    func testClubCountryCanUseDomesticTeamOrGroupReferenceWithoutVenue() {
        for referenceKey in ["$ref", "groups"] {
            let reference = "http://sports.core.api.espn.com/v2/sports/soccer/leagues/slv.1/seasons/2026/teams/7232"
            var root: [String: Any] = [
                "id": "7232", "displayName": "Luis Ángel Firpo", "location": "Luis Ángel Firpo",
                "abbreviation": "LAF", "isNational": false,
            ]
            root[referenceKey] = referenceKey == "$ref" ? reference : ["$ref": reference]
            XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), "El Salvador")
        }
    }

    func testKnownClubsKeepCorrectFlagsWhenESPNOmitsCountryOrReportsTouringVenue() {
        let cases = [
            ("493", "Shakhtar", "SHK", "Ukraine", "🇺🇦"),
            ("494", "Slavia Prague", "SLP", "Czech Republic", "🇨🇿"),
            ("521", "S Bratislava", "SLB", "Slovakia", "🇸🇰"),
            ("21922", "Sabah", "SAB", "Azerbaijan", "🇦🇿"),
        ]
        for (id, name, abbreviation, country, flag) in cases {
            let team = FootballTeamSummary(
                id: id, name: name, abbreviation: abbreviation, logoURL: nil,
                countryName: id == "493" ? "Hungary" : nil, isNational: false
            )
            XCTAssertEqual(FootballFixtureFormatter.teamFlag(for: team), flag)
            XCTAssertEqual(
                team.withResolvedDetails(countryName: team.countryName, isNational: false, logoURL: nil).countryName,
                country
            )
            let root: [String: Any] = [
                "id": id, "displayName": name, "location": name, "isNational": false,
                "venue": ["address": ["city": "Budapest", "country": "Hungary"]],
            ]
            XCTAssertEqual(FootballDataAPIClient.resolvedTeamCountryName(from: root), country)
        }
    }

    func testVerifiedClubLookupDoesNotAssignCountryToNamesakesOrUnknownClubs() {
        XCTAssertNil(FootballClubCountryResolver.countryName(teamID: "different-sabah", name: "Sabah"))
        XCTAssertNil(FootballClubCountryResolver.countryName(teamID: "21922", name: "Different club"))
        XCTAssertNil(FootballDataAPIClient.resolvedTeamCountryName(from: [
            "id": "unknown", "displayName": "Unknown Club", "location": "Unknown Club",
            "isNational": false,
            "$ref": "https://sports.core.api.espn.com/v2/sports/soccer/leagues/uefa.champions/teams/unknown",
        ]))
    }

    func testIncompletePersistedTeamCacheRetriesSoonerThanCompleteCountryData() async throws {
        let now = Date()
        let store = FootballTeamCacheStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("football-country-cache-\(UUID().uuidString).json"))
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        store.save([
            "incomplete": .init(
                response: .init(countryName: nil, isNational: false, logoURL: nil, venueLocationText: nil),
                fetchedAt: now
            ),
            "complete": .init(
                response: .init(countryName: "Spain", isNational: false, logoURL: nil, venueLocationText: nil),
                fetchedAt: now
            ),
        ])
        let session = makeMockSession { _ in throw URLError(.notConnectedToInternet) }
        let client = FootballDataAPIClient(session: session, teamCacheStore: store)
        let recentIncomplete = await client.hasFreshCachedTeam("incomplete", now: now.addingTimeInterval(14 * 60))
        let staleIncomplete = await client.hasFreshCachedTeam("incomplete", now: now.addingTimeInterval(16 * 60))
        let complete = await client.hasFreshCachedTeam("complete", now: now.addingTimeInterval(24 * 60 * 60))
        XCTAssertTrue(recentIncomplete)
        XCTAssertFalse(staleIncomplete)
        XCTAssertTrue(complete)
    }

    func testScheduledFixtureRecoversFlagFromStaleIncompleteTeamCache() async throws {
        let store = FootballTeamCacheStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("football-country-recovery-\(UUID().uuidString).json"))
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        store.save(["86": .init(
            response: .init(countryName: nil, isNational: false, logoURL: nil, venueLocationText: nil),
            fetchedAt: Date().addingTimeInterval(-3600)
        )])
        let session = makeMockSession { request in
            XCTAssertEqual(request.url?.path, "/v2/sports/soccer/teams/86")
            return try self.jsonResponse(for: request, body: [
                "id": "86", "displayName": "Real Madrid", "location": "Real Madrid", "isNational": false,
                "$ref": "https://sports.core.api.espn.com/v2/sports/soccer/leagues/esp.1/seasons/2026/teams/86",
            ])
        }
        let team = FootballTeamSummary(
            id: "86", name: "Real Madrid", abbreviation: "RMA", logoURL: nil, countryName: nil, isNational: false
        )
        let match = FootballTestData.match(id: "scheduled", statusState: .scheduled, homeTeam: team, awayTeam: team)
        let client = FootballDataAPIClient(session: session, teamCacheStore: store)
        let matches = await client.enrichTeams(in: [match])
        let recovered = try XCTUnwrap(matches.first)
        XCTAssertEqual(recovered.homeTeam.countryName, "Spain")
        XCTAssertEqual(FootballFixtureFormatter.calendarTitle(for: recovered), "RMA 🇪🇸 - 🇪🇸 RMA")
    }
}
