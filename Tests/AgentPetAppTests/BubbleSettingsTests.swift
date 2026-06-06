import XCTest
@testable import agentpet

@MainActor
final class BubbleSettingsTests: XCTestCase {
    private let multiAgentBubbleKey = "agentpet.bubble.multiAgentBubbleEnabled"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: multiAgentBubbleKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: multiAgentBubbleKey)
        super.tearDown()
    }

    func testMultiAgentBubbleDefaultsOn() {
        let settings = BubbleSettings()

        XCTAssertTrue(settings.multiAgentBubbleEnabled)
    }

    func testMultiAgentBubblePersists() {
        let settings = BubbleSettings()

        settings.multiAgentBubbleEnabled = true

        XCTAssertTrue(BubbleSettings().multiAgentBubbleEnabled)
    }
}
