import XCTest
@testable import agentpet

@MainActor
final class QuotaControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "agentpet.quotaTracker.enabled")
    }

    func testQuotaTrackerDefaultsDisabled() {
        let controller = QuotaController()

        XCTAssertFalse(controller.trackerEnabled)
    }

    func testRefreshNoopsWhenTrackerDisabled() {
        let controller = QuotaController()

        controller.refresh()

        XCTAssertFalse(controller.isRefreshing)
        XCTAssertTrue(controller.snapshots.isEmpty)
    }
}
