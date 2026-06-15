import XCTest
@testable import AlertCalendar

final class LocationCoordinateResolverTests: XCTestCase {
    func testSearchQueriesIncludeVenueAliasesWithLocationContext() {
        let queries = LocationCoordinateResolver.searchQueries(
            from: "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina"
        )

        XCTAssertTrue(queries.contains("Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina"))
        XCTAssertTrue(queries.contains("La Bombonera, Buenos Aires, Argentina"))
        XCTAssertTrue(queries.contains("Alberto Jose Armando, Buenos Aires, Argentina"))
    }

    func testSearchQueriesKeepsShortVenueAlias() {
        let queries = LocationCoordinateResolver.searchQueries(
            from: "Mercedes-Benz Stadium, Atlanta, Georgia, USA"
        )

        XCTAssertTrue(queries.contains("Mercedes-Benz Stadium"))
        XCTAssertTrue(queries.contains("Atlanta, Georgia, USA"))
    }

    func testSearchQueriesAddsQualifiedVenueVariantsForAmbiguousStadiumNames() {
        let queries = LocationCoordinateResolver.searchQueries(
            from: "Santiago Bernabéu, Madrid, Spain"
        )

        XCTAssertTrue(queries.contains("Santiago Bernabéu Stadium, Madrid, Spain"))
        XCTAssertTrue(queries.contains("Estadio Santiago Bernabéu, Madrid, Spain"))
    }

    func testSearchQueriesAddsStadiumVariantForSimpleGroundNames() {
        let queries = LocationCoordinateResolver.searchQueries(
            from: "Anfield, Liverpool, England"
        )

        XCTAssertTrue(queries.contains("Anfield Stadium, Liverpool, England"))
        XCTAssertTrue(queries.contains("Anfield, Liverpool, England"))
    }

    func testSearchQueriesAddsEstadioVariantForArenaVenues() {
        let queries = LocationCoordinateResolver.searchQueries(
            from: "Arena da Baixada, Curitiba, Brazil"
        )

        XCTAssertTrue(queries.contains("Estadio Arena da Baixada, Curitiba, Brazil"))
        XCTAssertTrue(queries.contains("Arena da Baixada, Curitiba, Brazil"))
    }

    func testStrictSearchQueriesAvoidsLooseVenueFallbacksWhenContextExists() {
        let queries = LocationCoordinateResolver.strictSearchQueries(
            from: "Mercedes-Benz Stadium, Atlanta, Georgia, USA"
        )

        XCTAssertTrue(queries.contains("Mercedes-Benz Stadium, Atlanta, Georgia, USA"))
        XCTAssertFalse(queries.contains("Atlanta, Georgia, USA"))
        XCTAssertFalse(queries.contains("Mercedes-Benz Stadium"))
    }

    func testStrictSearchQueriesKeepsContextualVenueAliases() {
        let queries = LocationCoordinateResolver.strictSearchQueries(
            from: "Alberto Jose Armando (La Bombonera), Buenos Aires, Argentina"
        )

        XCTAssertTrue(queries.contains("La Bombonera, Buenos Aires, Argentina"))
        XCTAssertFalse(queries.contains("La Bombonera"))
    }

    func testSearchConfidenceRejectsContextOnlyMatchForVenueQuery() {
        XCTAssertFalse(
            LocationCoordinateResolver.isConfidentSearchMatch(
                query: "Mercedes-Benz Stadium, Atlanta, Georgia, USA",
                candidateFields: ["Atlanta", "Georgia", "United States"]
            )
        )
    }

    func testSearchConfidenceAcceptsVenueAndContextMatch() {
        XCTAssertTrue(
            LocationCoordinateResolver.isConfidentSearchMatch(
                query: "Mercedes-Benz Stadium, Atlanta, Georgia, USA",
                candidateFields: ["Mercedes-Benz Stadium", "Atlanta", "Georgia", "United States"]
            )
        )
    }

    func testSearchConfidenceAcceptsVenueDescriptorWithContextForRenamedStadium() {
        XCTAssertTrue(
            LocationCoordinateResolver.isConfidentSearchMatch(
                query: "Estadio Banorte, Mexico City, Mexico",
                candidateFields: ["Estadio Azteca", "Mexico City", "Mexico"]
            )
        )
    }

    func testSearchConfidenceRejectsCountryMismatchEvenWithVenueAndCityMatch() {
        XCTAssertFalse(
            LocationCoordinateResolver.isConfidentSearchMatch(
                query: "Estadio BBVA, Guadalupe, Mexico",
                candidateFields: ["Estadio BBVA", "Guadalupe", "New Mexico", "United States"]
            )
        )
    }

    func testKnownAmbiguousVenueResolvesToStadiumCoordinate() async {
        let coordinate = await LocationCoordinateResolver.shared.coordinate(
            for: "Estadio BBVA, Guadalupe, Mexico"
        )

        XCTAssertEqual(coordinate?.latitude ?? 0, 25.668565, accuracy: 0.0001)
        XCTAssertEqual(coordinate?.longitude ?? 0, -100.244545, accuracy: 0.0001)
    }

    func testKnownAmbiguousVenueResolvesTimeZone() async {
        let timeZone = await LocationCoordinateResolver.shared.timeZone(
            for: "Estadio BBVA, Guadalupe, Mexico"
        )

        XCTAssertEqual(timeZone?.identifier, "America/Monterrey")
    }
}
