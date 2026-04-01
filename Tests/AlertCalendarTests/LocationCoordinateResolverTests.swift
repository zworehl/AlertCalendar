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
}
