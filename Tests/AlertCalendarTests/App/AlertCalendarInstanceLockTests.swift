import Foundation
import XCTest
@testable import AlertCalendar

@MainActor
final class AlertCalendarInstanceLockTests: XCTestCase {
    func testOnlyOneInstanceCanOwnLockAndRepeatedAcquisitionIsSafe() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("instance.lock")
        let first = AlertCalendarInstanceLock(fileURL: url)
        let second = AlertCalendarInstanceLock(fileURL: url)

        XCTAssertTrue(try first.acquire())
        XCTAssertTrue(try first.acquire())
        XCTAssertFalse(try second.acquire())
    }

    func testLockCanBeAcquiredAfterOwnerExitsEvenWhenFileRemains() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("instance.lock")
        var first: AlertCalendarInstanceLock? = AlertCalendarInstanceLock(fileURL: url)
        XCTAssertTrue(try XCTUnwrap(first).acquire())
        first = nil

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try AlertCalendarInstanceLock(fileURL: url).acquire())
    }
}
