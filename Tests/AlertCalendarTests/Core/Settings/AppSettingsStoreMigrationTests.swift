import Foundation
import XCTest
@testable import AlertCalendar

final class AppSettingsStoreMigrationTests: XCTestCase {
    func testRegisterDefaultsRemovesLegacyFocusFilterState() {
        let suiteName = "AppSettingsStoreMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(Data([1, 2, 3]), forKey: "activeFocusCalendarFilterState")

        AppSettingsStore(defaults: defaults).registerDefaults()

        XCTAssertNil(defaults.object(forKey: "activeFocusCalendarFilterState"))
    }
}
