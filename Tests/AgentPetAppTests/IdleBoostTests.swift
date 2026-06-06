import XCTest
@testable import agentpet

final class IdleBoostTests: XCTestCase {
    func testSystemLinesIncludeJokesAndMotivation() {
        XCTAssertTrue(IdleBoost.lines.contains("Let's grill some bugs."))
        XCTAssertTrue(IdleBoost.lines.contains("I miss you. Ship something for me."))
    }

    func testLineSelectionIsStableInsideSameWindow() {
        let now = Date(timeIntervalSince1970: 120)

        XCTAssertEqual(
            IdleBoost.line(at: now),
            IdleBoost.line(at: now.addingTimeInterval(59))
        )
    }

    func testLineSelectionRotatesAcrossWindows() {
        let first = IdleBoost.line(at: Date(timeIntervalSince1970: 0))
        let later = IdleBoost.line(at: Date(timeIntervalSince1970: 60))

        XCTAssertNotEqual(first, later)
    }
}
