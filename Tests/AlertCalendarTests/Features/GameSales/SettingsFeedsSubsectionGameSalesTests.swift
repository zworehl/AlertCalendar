import XCTest
@testable import AlertCalendar

final class SettingsFeedsSubsectionGameSalesTests: XCTestCase {
    func testGameSalesFeedSubsectionMetadataAndOrder() {
        XCTAssertEqual(
            SettingsView.FeedsSubsection.allCases.map(\.rawValue),
            ["Atmosphere", "Holidays", "Football", "Game Sales"]
        )
        XCTAssertEqual(SettingsView.FeedsSubsection.gameSales.id, "Game Sales")
        XCTAssertEqual(SettingsView.FeedsSubsection.gameSales.title, "Game Sales")
        XCTAssertEqual(SettingsView.FeedsSubsection.gameSales.symbolName, "gamecontroller.fill")
    }
}
