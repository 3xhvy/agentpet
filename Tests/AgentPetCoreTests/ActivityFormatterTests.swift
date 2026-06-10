import XCTest
@testable import AgentPetCore

final class ActivityFormatterTests: XCTestCase {

    // MARK: - Rotation

    func test_rotation_doesNotRepeatConsecutively() {
        let first = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "rot1",
            toolName: "Read", toolInput: nil, explicitMessage: nil
        )
        let second = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "rot1",
            toolName: "Read", toolInput: nil, explicitMessage: nil
        )
        XCTAssertNotEqual(first, second, "consecutive calls same tool should rotate")
    }

    func test_rotation_cyclesFullPool() {
        // reading pool has 5 phrases — 5 distinct calls must yield 5 distinct phrases
        let poolSize = 5
        var seen = Set<String?>()
        for _ in 0..<poolSize {
            let msg = ActivityFormatter.activityMessage(
                eventName: "PreToolUse", sessionId: "rot2",
                toolName: "Read", toolInput: nil, explicitMessage: nil
            )
            seen.insert(msg)
        }
        XCTAssertEqual(seen.count, poolSize, "should cycle through all \(poolSize) reading phrases")
    }

    // MARK: - Extension hints

    func test_extensionHint_testFile_reading() {
        let input = ToolActivityInput(filePath: "Tests/FooTests/BarTests.swift")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext1",
            toolName: "Read", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Reviewing tests…")
    }

    func test_extensionHint_testFile_writing() {
        let input = ToolActivityInput(filePath: "Tests/FooTests/BarTests.swift")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext2",
            toolName: "Edit", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Refining tests…")
    }

    func test_extensionHint_markdown_reading() {
        let input = ToolActivityInput(filePath: "README.md")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext3",
            toolName: "Read", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Reading the docs…")
    }

    func test_extensionHint_markdown_writing() {
        let input = ToolActivityInput(filePath: "docs/guide.md")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext4",
            toolName: "Write", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Updating the docs…")
    }

    func test_extensionHint_json_reading() {
        let input = ToolActivityInput(filePath: "config/settings.json")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext5",
            toolName: "Read", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Parsing config…")
    }

    func test_extensionHint_plist_writing() {
        let input = ToolActivityInput(filePath: "Info.plist")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext6",
            toolName: "Edit", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Adjusting config…")
    }

    // MARK: - State messages

    func test_stateMessage_done_returnsPhrase() {
        XCTAssertNotNil(ActivityFormatter.stateMessage(for: .done))
    }

    func test_stateMessage_waiting_returnsPhrase() {
        XCTAssertNotNil(ActivityFormatter.stateMessage(for: .waiting))
    }

    func test_stateMessage_idle_returnsNil() {
        XCTAssertNil(ActivityFormatter.stateMessage(for: .idle))
    }

    func test_stateMessage_working_returnsNil() {
        XCTAssertNil(ActivityFormatter.stateMessage(for: .working))
    }

    func test_stateMessage_done_rotates() {
        let first  = ActivityFormatter.stateMessage(for: .done)
        let second = ActivityFormatter.stateMessage(for: .done)
        XCTAssertNotEqual(first, second, "done phrases should rotate")
    }
}
