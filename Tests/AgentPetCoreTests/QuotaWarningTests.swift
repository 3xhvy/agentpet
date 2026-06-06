import XCTest
@testable import AgentPetCore

final class QuotaWarningTests: XCTestCase {
    func testCreatesWarningWhenRemainingQuotaIsAtThreshold() {
        let snapshot = QuotaSnapshot(
            provider: .codex,
            displayName: "Codex",
            buckets: [
                QuotaBucket(name: "weekly", used: 82, total: 100, remainingPercentage: 18)
            ],
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        let events = QuotaWarning.events(in: [snapshot], thresholdRemainingPercentage: 20)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.message, "Codex quota is down to 18% (weekly). Use it carefully.")
    }

    func testIgnoresHealthyAndUnlimitedQuota() {
        let snapshot = QuotaSnapshot(
            provider: .claude,
            displayName: "Claude",
            buckets: [
                QuotaBucket(name: "weekly", used: 40, total: 100, remainingPercentage: 60),
                QuotaBucket(name: "unlimited", used: 0, total: 0, remainingPercentage: 0, unlimited: true),
            ],
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        let events = QuotaWarning.events(in: [snapshot], thresholdRemainingPercentage: 20)

        XCTAssertTrue(events.isEmpty)
    }
}
