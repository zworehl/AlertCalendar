import Foundation
import XCTest
@testable import AlertCalendar

final class ExternalFeedMetricsTests: XCTestCase {
    func testValidatedAndAppliedDataAreSeparateFromHTTP200() async {
        let metrics = ExternalFeedMetrics()
        let old = Date(timeIntervalSince1970: 100)
        await metrics.recordValidatedData(source: "one", at: old)
        await metrics.recordNetworkResponse(source: "one", statusCode: 200, responseBytes: 20, at: old.addingTimeInterval(10))
        await metrics.recordDataFailure(source: "one", validationFailed: true)
        var snapshot = await metrics.snapshot()
        XCTAssertEqual(snapshot.sources["one"]?.lastDataDate, old)
        XCTAssertNil(snapshot.sources["one"]?.lastAppliedDate)
        XCTAssertTrue(snapshot.hasUnresolvedFailure(sourcePrefix: "one"))
        await metrics.recordValidatedData(source: "one", at: old.addingTimeInterval(20))
        await metrics.recordAppliedData(source: "one", at: old.addingTimeInterval(21))
        snapshot = await metrics.snapshot()
        XCTAssertEqual(snapshot.sources["one"]?.lastAppliedDate, old.addingTimeInterval(21))
        XCTAssertFalse(snapshot.hasUnresolvedFailure(sourcePrefix: "one"))
    }

    func testOldestValidatedSourceDoesNotHidePartialOrUnknownData() async {
        let metrics = ExternalFeedMetrics()
        let old = Date(timeIntervalSince1970: 100)
        await metrics.recordValidatedData(source: "feed.one", at: old)
        await metrics.recordValidatedData(source: "feed.two", at: old.addingTimeInterval(50))
        var snapshot = await metrics.snapshot()
        XCTAssertEqual(snapshot.oldestDataDate(sourcePrefix: "feed."), old)
        await metrics.recordTransportFailure(source: "feed.three")
        snapshot = await metrics.snapshot()
        XCTAssertNil(snapshot.oldestDataDate(sourcePrefix: "feed."))
        XCTAssertTrue(snapshot.hasUnresolvedFailure(sourcePrefix: "feed."))
    }

    func testMetricsSeparateChecksDataFreshnessAndLatencyPercentiles() async {
        let metrics = ExternalFeedMetrics()
        let checkedAt = Date(timeIntervalSince1970: 100)
        let cachedAt = Date(timeIntervalSince1970: 80)

        await metrics.recordCheck(source: "feed.one", at: checkedAt)
        await metrics.recordCacheHit(source: "feed.one", dataDate: cachedAt, at: checkedAt)
        await metrics.recordNetworkResponse(
            source: "feed.one",
            statusCode: 200,
            responseBytes: 10,
            duration: 1,
            at: Date(timeIntervalSince1970: 101)
        )
        await metrics.recordTransportFailure(
            source: "feed.two",
            duration: 3,
            at: Date(timeIntervalSince1970: 102)
        )

        let snapshot = await metrics.snapshot()
        XCTAssertEqual(snapshot.sources["feed.one"]?.checks, 1)
        XCTAssertEqual(snapshot.latestCheckedDate(sourcePrefix: "feed."), Date(timeIntervalSince1970: 102))
        XCTAssertEqual(snapshot.latestSuccessfulRequestDate(sourcePrefix: "feed."), Date(timeIntervalSince1970: 101))
        XCTAssertEqual(snapshot.latestDataDate(sourcePrefix: "feed."), cachedAt)
        XCTAssertEqual(snapshot.medianRequestDuration, 1)
        XCTAssertEqual(snapshot.p95RequestDuration, 3)
    }
}
