import XCTest
@testable import AlertCalendar

final class RelevantContextSelectorTests: XCTestCase {
    func testSelectsRelevantTailAcrossCompleteLongText() throws {
        let filler = (0..<800)
            .map { "Unrelated policy paragraph \($0) about standard procedures." }
            .joined(separator: "\n")
        let selected = try XCTUnwrap(
            RelevantContextSelector.selectedText(
                from: """
                \(filler)
                Route: San José to Miami
                Booking type: Direct flight reservation
                """,
                referenceText: ["Family flight reservation to Miami"],
                maximumCharacters: 700,
                maximumSegments: 8
            )
        )

        XCTAssertTrue(selected.contains("San José to Miami"))
        XCTAssertTrue(selected.contains("Direct flight reservation"))
        XCTAssertLessThanOrEqual(selected.count, 700)
    }

    func testPreservesAllShortStructuredContextAndRedactsPrivateValues() throws {
        let selected = try XCTUnwrap(
            RelevantContextSelector.selectedText(
                from: """
                Type: Prueba Teórica
                Course: SUFICIENCIA MOTOS
                Identification: 702070452
                Contact: owner@example.com
                Details: https://example.com/private
                """,
                referenceText: ["driving license test"],
                maximumCharacters: 1_000,
                maximumSegments: 20
            )
        )

        XCTAssertTrue(selected.contains("Prueba Teórica"))
        XCTAssertTrue(selected.contains("SUFICIENCIA MOTOS"))
        XCTAssertTrue(selected.contains("[number]"))
        XCTAssertTrue(selected.contains("[email]"))
        XCTAssertTrue(selected.contains("[link]"))
        XCTAssertFalse(selected.contains("702070452"))
        XCTAssertFalse(selected.contains("owner@example.com"))
    }
}
