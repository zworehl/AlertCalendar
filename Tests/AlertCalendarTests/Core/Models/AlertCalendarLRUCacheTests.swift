import XCTest
@testable import AlertCalendar

final class AlertCalendarLRUCacheTests: XCTestCase {
    func testEvictsLeastRecentlyUsedValueAtCapacity() {
        var cache = AlertCalendarLRUCache<String, Int>(capacity: 2)
        cache.insert(1, forKey: "one")
        cache.insert(2, forKey: "two")

        XCTAssertEqual(cache.value(forKey: "one"), 1)
        cache.insert(3, forKey: "three")

        XCTAssertNil(cache.value(forKey: "two"))
        XCTAssertEqual(cache.value(forKey: "one"), 1)
        XCTAssertEqual(cache.value(forKey: "three"), 3)
        XCTAssertEqual(cache.count, 2)
    }

    func testReplacingValueKeepsCacheBoundedAndMakesKeyRecent() {
        var cache = AlertCalendarLRUCache<String, Int>(capacity: 2)
        cache.insert(1, forKey: "one")
        cache.insert(2, forKey: "two")
        cache.insert(10, forKey: "one")
        cache.insert(3, forKey: "three")

        XCTAssertEqual(cache.value(forKey: "one"), 10)
        XCTAssertNil(cache.value(forKey: "two"))
        XCTAssertEqual(cache.value(forKey: "three"), 3)
    }

    func testCapacityIsNeverBelowOne() {
        var cache = AlertCalendarLRUCache<String, Int>(capacity: 0)
        cache.insert(1, forKey: "one")
        cache.insert(2, forKey: "two")

        XCTAssertEqual(cache.capacity, 1)
        XCTAssertNil(cache.value(forKey: "one"))
        XCTAssertEqual(cache.value(forKey: "two"), 2)
    }
}
