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
}
