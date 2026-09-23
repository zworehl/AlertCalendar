import Foundation
import XCTest
@testable import AlertCalendar

final class ExternalFeedMetricsTests: XCTestCase {
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
        XCTAssertEqual(snapshot.latestDataDate(sourcePrefix: "feed."), Date(timeIntervalSince1970: 101))
        XCTAssertEqual(snapshot.medianRequestDuration, 1)
        XCTAssertEqual(snapshot.p95RequestDuration, 3)
    }
}
