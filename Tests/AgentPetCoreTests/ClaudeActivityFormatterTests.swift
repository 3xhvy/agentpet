import XCTest
@testable import AgentPetCore

final class ClaudeActivityFormatterTests: XCTestCase {

    func testReadUsesWhimsicalPhraseNotPath() {
        let msg = ClaudeActivityFormatter.activityMessage(
            eventName: "PreToolUse",
            sessionId: "s1",
            toolName: "Read",
            toolInput: ClaudeToolInput(
                filePath: "/proj/web/src/pages/landing/i18n/en.ts",
                command: nil, description: nil, pattern: nil, query: nil, url: nil,
                prompt: nil, subagentType: nil
            ),
            explicitMessage: nil
        )
        XCTAssertTrue(ClaudeActivityFormatterTests.readingPhrases.contains(msg ?? ""))
    }

    func testEditUsesWhimsicalPhraseNotPath() {
        let msg = ClaudeActivityFormatter.activityMessage(
            eventName: "PreToolUse",
            sessionId: "s1",
            toolName: "Edit",
            toolInput: ClaudeToolInput(
                filePath: "/proj/src/foo.swift",
                command: nil, description: nil, pattern: nil, query: nil, url: nil,
                prompt: nil, subagentType: nil
            ),
            explicitMessage: nil
        )
        XCTAssertTrue(ClaudeActivityFormatterTests.writingPhrases.contains(msg ?? ""))
    }

    func testBashUsesWhimsicalPhraseNotCommand() {
        let msg = ClaudeActivityFormatter.activityMessage(
            eventName: "PreToolUse",
            sessionId: "s1",
            toolName: "Bash",
            toolInput: ClaudeToolInput(
                filePath: nil,
                command: "npm test -- --watch",
                description: "Run test suite",
                pattern: nil, query: nil, url: nil, prompt: nil, subagentType: nil
            ),
            explicitMessage: nil
        )
        XCTAssertTrue(ClaudeActivityFormatterTests.runningPhrases.contains(msg ?? ""))
    }

    func testUserPromptSubmitUsesThinkingPhrase() {
        let msg = ClaudeActivityFormatter.activityMessage(
            eventName: "UserPromptSubmit",
            sessionId: "s1",
            toolName: nil,
            toolInput: nil,
            explicitMessage: nil
        )
        XCTAssertTrue(ClaudeActivityFormatterTests.thinkingPhrases.contains(msg ?? ""))
    }

    func testNotificationUsesMessage() {
        let msg = ClaudeActivityFormatter.activityMessage(
            eventName: "Notification",
            sessionId: "s1",
            toolName: nil,
            toolInput: nil,
            explicitMessage: "Claude is waiting for your input"
        )
        XCTAssertEqual(msg, "Claude is waiting for your input")
    }

    func testPayloadEndToEnd() {
        let json = """
        {"session_id":"s1","cwd":"/proj","hook_event_name":"PreToolUse",\
        "tool_name":"Read","tool_input":{"file_path":"/proj/README.md"}}
        """
        let event = ClaudeHookPayload.decode(from: Data(json.utf8))?.makeEvent(now: .now)
        XCTAssertTrue(ClaudeActivityFormatterTests.readingPhrases.contains(event?.message ?? ""))
    }

    func testSameSeedIsStable() {
        let input = ClaudeToolInput(
            filePath: "/proj/a.swift",
            command: nil, description: nil, pattern: nil, query: nil, url: nil,
            prompt: nil, subagentType: nil
        )
        let a = ClaudeActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "s1", toolName: "Read",
            toolInput: input, explicitMessage: nil
        )
        let b = ClaudeActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "s1", toolName: "Read",
            toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(a, b)
    }

    // Mirrors private phrase pools for assertions.
    private static let thinkingPhrases = [
        "Photosynthesizing…", "Sprouting…", "Planning…", "Pondering…",
        "Germinating…", "Marinating…", "Noodling…",
    ]
    private static let readingPhrases = [
        "Perusing…", "Leafing through…", "Absorbing…", "Studying…", "Browsing…",
    ]
    private static let writingPhrases = [
        "Cooking…", "Baking…", "Crafting…", "Whittling…", "Sculpting…", "Stitching…",
    ]
    private static let runningPhrases = [
        "Brewing…", "Simmering…", "Stirring the pot…", "Running the numbers…",
    ]
}
