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

    public init(
        filePath: String? = nil, command: String? = nil, description: String? = nil,
        pattern: String? = nil, query: String? = nil, url: String? = nil,
        prompt: String? = nil, subagentType: String? = nil
    ) {
        self.filePath = filePath; self.command = command; self.description = description
        self.pattern = pattern; self.query = query; self.url = url
        self.prompt = prompt; self.subagentType = subagentType
    }

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
            return pick(from: thinking, key: eventName)
        case "PreToolUse", "PostToolUse":
            return toolActivity(toolName: toolName, toolInput: toolInput)
        default:
            if toolName != nil {
                return toolActivity(toolName: toolName, toolInput: toolInput)
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
        toolName: String?,
        toolInput: ClaudeToolInput?
    ) -> String? {
        guard let toolName else { return nil }
        if let hint = extensionHint(toolName: toolName, filePath: toolInput?.filePath) { return hint }
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
        return pick(from: phrases, key: toolName)
    }

    private static func extensionHint(toolName: String, filePath: String?) -> String? {
        guard let path = filePath else { return nil }
        let lower = path.lowercased()
        let isTest = lower.contains("tests/") || lower.hasSuffix("tests.swift") || lower.hasSuffix("test.swift")
        let isDoc  = lower.hasSuffix(".md") || lower.hasSuffix(".txt") || lower.hasSuffix(".rst")
        let isCfg  = lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml")
                  || lower.hasSuffix(".plist") || lower.hasSuffix(".toml")
        let isRead  = toolName == "Read"
        let isWrite = toolName == "Edit" || toolName == "Write" || toolName == "MultiEdit"
        if isTest  && isRead  { return "Reviewing tests…" }
        if isTest  && isWrite { return "Refining tests…" }
        if isDoc   && isRead  { return "Reading the docs…" }
        if isDoc   && isWrite { return "Updating the docs…" }
        if isCfg   && isRead  { return "Parsing config…" }
        if isCfg   && isWrite { return "Adjusting config…" }
        return nil
    }

    private static let doneMessages = [
        "All done!", "Wrapped up!", "Delivered!", "Finished!", "Mission complete!",
    ]
    private static let waitingMessages = [
        "Awaiting instructions…", "Standing by…", "Listening…",
    ]

    public static func stateMessage(for state: AgentState) -> String? {
        switch state {
        case .done:    return pick(from: doneMessages,    key: "state.done")
        case .waiting: return pick(from: waitingMessages, key: "state.waiting")
        default:       return nil
        }
    }

    nonisolated(unsafe) private static var callCounts: [String: Int] = [:]

    private static func pick(from phrases: [String], key: String) -> String {
        guard !phrases.isEmpty else { return "Working…" }
        let n = (callCounts[key, default: 0] + 1) % phrases.count
        callCounts[key] = n
        return phrases[n]
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}
