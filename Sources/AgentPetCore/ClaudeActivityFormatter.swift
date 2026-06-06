import Foundation

/// Tool arguments Claude Code sends on PreToolUse / PostToolUse hooks.
public struct ClaudeToolInput: Decodable, Equatable, Sendable {
    public let filePath: String?
    public let command: String?
    public let description: String?
    public let pattern: String?
    public let query: String?
    public let url: String?
    public let prompt: String?
    public let subagentType: String?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case command, description, pattern, query, url, prompt
        case subagentType = "subagent_type"
    }
}

/// Turns Claude Code hook payloads into whimsical activity lines
/// (e.g. "Cooking…", "Sprouting…") instead of file paths or tool names.
public enum ClaudeActivityFormatter {

    public static func activityMessage(
        eventName: String,
        sessionId: String,
        toolName: String?,
        toolInput: ClaudeToolInput?,
        explicitMessage: String?
    ) -> String? {
        if eventName == "Notification" {
            return trimmed(explicitMessage)
        }

        switch eventName {
        case "UserPromptSubmit":
            return pick(from: thinking, seed: seed(sessionId, eventName, toolName, toolInput))
        case "PreToolUse", "PostToolUse":
            return toolActivity(
                sessionId: sessionId,
                eventName: eventName,
                toolName: toolName,
                toolInput: toolInput
            )
        default:
            if let toolName {
                return toolActivity(
                    sessionId: sessionId,
                    eventName: eventName,
                    toolName: toolName,
                    toolInput: toolInput
                )
            }
            return trimmed(explicitMessage)
        }
    }

    private static let thinking = [
        "Photosynthesizing…",
        "Sprouting…",
        "Planning…",
        "Pondering…",
        "Germinating…",
        "Marinating…",
        "Noodling…",
    ]

    private static let reading = [
        "Perusing…",
        "Leafing through…",
        "Absorbing…",
        "Studying…",
        "Browsing…",
    ]

    private static let writing = [
        "Cooking…",
        "Baking…",
        "Crafting…",
        "Whittling…",
        "Sculpting…",
        "Stitching…",
    ]

    private static let running = [
        "Brewing…",
        "Simmering…",
        "Stirring the pot…",
        "Running the numbers…",
    ]

    private static let searching = [
        "Foraging…",
        "Scouting…",
        "Hunting…",
        "Exploring…",
        "Investigating…",
    ]

    private static let delegating = [
        "Delegating…",
        "Hatching a plan…",
        "Spawning help…",
        "Rounding up agents…",
    ]

    private static let generic = [
        "Working…",
        "Tinkering…",
        "Doing the thing…",
    ]

    private static func toolActivity(
        sessionId: String,
        eventName: String,
        toolName: String?,
        toolInput: ClaudeToolInput?
    ) -> String? {
        guard let toolName else { return nil }
        let phrases: [String]
        switch toolName {
        case "Read":
            phrases = reading
        case "Edit", "Write", "MultiEdit":
            phrases = writing
        case "Bash":
            phrases = running
        case "Glob", "Grep", "WebSearch", "WebFetch":
            phrases = searching
        case "Agent", "Task":
            phrases = delegating
        case "Skill":
            phrases = ["Consulting the scrolls…", "Channeling a skill…", "Reading the manual…"]
        default:
            phrases = generic
        }
        return pick(from: phrases, seed: seed(sessionId, eventName, toolName, toolInput))
    }

    private static func seed(
        _ sessionId: String,
        _ eventName: String,
        _ toolName: String?,
        _ toolInput: ClaudeToolInput?
    ) -> String {
        [
            sessionId,
            eventName,
            toolName ?? "",
            toolInput?.filePath ?? "",
            toolInput?.command ?? "",
            toolInput?.pattern ?? "",
            toolInput?.query ?? "",
        ].joined(separator: "|")
    }

    private static func pick(from phrases: [String], seed: String) -> String {
        guard !phrases.isEmpty else { return "Working…" }
        let hash = seed.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }
        return phrases[abs(hash) % phrases.count]
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}
