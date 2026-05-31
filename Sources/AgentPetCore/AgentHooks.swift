import Foundation

/// Where and which lifecycle events to register for an agent. All three CLIs
/// share the same hook config shape (`{"hooks": {...}}`) and stdin field names.
public struct AgentHookSpec {
    public let kind: AgentKind
    public let events: [String]
    public let settingsPath: String
}

public enum AgentHooks {
    public static func spec(for kind: AgentKind) -> AgentHookSpec? {
        let home = NSHomeDirectory()
        switch kind {
        case .claude:
            return AgentHookSpec(
                kind: .claude,
                events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SubagentStop"],
                settingsPath: home + "/.claude/settings.json")
        case .codex:
            return AgentHookSpec(
                kind: .codex,
                events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "SubagentStop"],
                settingsPath: home + "/.codex/hooks.json")
        case .gemini:
            return AgentHookSpec(
                kind: .gemini,
                events: ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"],
                settingsPath: home + "/.gemini/settings.json")
        case .cli, .unknown:
            return nil
        }
    }
}
