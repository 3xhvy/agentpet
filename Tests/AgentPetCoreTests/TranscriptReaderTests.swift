import XCTest
@testable import AgentPetCore

final class TranscriptReaderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TranscriptReader.clearCache()
    }

    func testLatestAssistantRecapUsesLastAssistantTextAndCollapsesToOneLine() throws {
        let path = try writeTranscript("""
        {"type":"assistant","message":{"content":[{"type":"text","text":"First answer"}]}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"※ recap: Redesigned the tenant side UI.\\nThe home debt card is now white with a red amount and teal Pay Now button.\\nNext: verify the no-debt card state looks right too."}]}}
        """)

        let recap = TranscriptReader.latestAssistantRecap(at: path)

        XCTAssertEqual(
            recap,
            "Redesigned the tenant side UI. The home debt card is now white with a red amount and teal Pay Now button. Next: verify the no-debt card state looks right too."
        )
    }

    func testLatestAssistantRecapUsesClaudeDoneSummary() throws {
        let path = try writeTranscript("""
        {"type":"assistant","message":{"content":[{"type":"text","text":"Done. Summary of all changes:\\n\\n**Hero** - simplified to badge, headline, sub, CTAs.\\n**Eyebrows** - cut down to 3 items."}]}}
        """)

        let recap = TranscriptReader.latestAssistantRecap(at: path)

        XCTAssertEqual(
            recap,
            "**Hero** - simplified to badge, headline, sub, CTAs. **Eyebrows** - cut down to 3 items."
        )
    }

    func testSessionStoreUsesClaudeStopRecapAsDoneMessage() throws {
        let path = try writeTranscript("""
        {"type":"assistant","message":{"content":[{"type":"text","text":"recap: Updated animation triggers and bubble radius."}]}}
        """)
        let store = SessionStore()
        let event = AgentEvent(
            sessionId: "s1",
            agentKind: .claude,
            eventName: "Stop",
            project: "/proj",
            message: nil,
            transcriptPath: path,
            timestamp: Date(timeIntervalSince1970: 1_000)
        )

        let session = store.apply(event, now: event.timestamp)

        XCTAssertEqual(session?.message, "Updated animation triggers and bubble radius.")
    }

    private func writeTranscript(_ text: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
