import Foundation

/// Maps an agent-native event name to a normalised `AgentState`.
///
/// Returns `nil` for events that should not change state (unknown or
/// irrelevant events are ignored rather than treated as an error).
public enum StateMapper {
    public static func state(for kind: AgentKind, eventName: String) -> AgentState? {
        // Generic: any caller (e.g. the `agentpet run` wrapper) can send a
        // normalised state name directly.
        if let direct = AgentState(rawValue: eventName) { return direct }

        switch kind {
        case .claude:
            switch eventName {
            case "SessionStart": return .registered
            case "UserPromptSubmit", "PreToolUse", "PostToolUse": return .working
            case "Notification": return .waiting
            case "Stop", "SubagentStop": return .done
            default: return nil
            }
        case .codex:
            switch eventName {
            case "SessionStart": return .registered
            case "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart": return .working
            case "PermissionRequest": return .waiting
            case "Stop", "SubagentStop": return .done
            default: return nil
            }
        case .gemini:
            switch eventName {
            case "SessionStart": return .registered
            case "BeforeAgent", "BeforeModel", "BeforeTool", "AfterTool", "BeforeToolSelection", "AfterModel": return .working
            case "Notification": return .waiting
            case "AfterAgent", "SessionEnd": return .done
            default: return nil
            }
        case .cli, .unknown:
            return nil
        }
    }
}
