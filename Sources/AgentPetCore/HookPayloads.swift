import Foundation

/// The JSON Cursor writes to a hook's stdin (only the fields AgentPet needs).
public struct CursorHookPayload: Decodable, Equatable {
    public let conversationId: String?
    public let hookEventName: String?
    public let workspaceRoots: [String]?
    public let toolName: String?
    public let toolInput: ToolActivityInput?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case hookEventName = "hook_event_name"
        case workspaceRoots = "workspace_roots"
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }

    public static func decode(from data: Data) -> CursorHookPayload? {
        try? JSONDecoder().decode(CursorHookPayload.self, from: data)
    }

    public func makeEvent(now: Date) -> AgentEvent? {
        guard let conversationId, let hookEventName else { return nil }
        let context = ActivityFormatter.activityMessage(
            eventName: hookEventName, sessionId: conversationId,
            toolName: toolName, toolInput: toolInput, explicitMessage: nil
        )
        return AgentEvent(
            sessionId: conversationId, agentKind: .cursor, eventName: hookEventName,
            project: workspaceRoots?.first, message: context, timestamp: now
        )
    }
}

/// The JSON Windsurf (Cascade) writes to a hook's stdin.
public struct WindsurfHookPayload: Decodable, Equatable {
    public let trajectoryId: String?
    public let agentActionName: String?

    enum CodingKeys: String, CodingKey {
        case trajectoryId = "trajectory_id"
        case agentActionName = "agent_action_name"
    }

    public static func decode(from data: Data) -> WindsurfHookPayload? {
        try? JSONDecoder().decode(WindsurfHookPayload.self, from: data)
    }

    public func makeEvent(now: Date) -> AgentEvent? {
        guard let trajectoryId, let agentActionName else { return nil }
        return AgentEvent(
            sessionId: trajectoryId, agentKind: .windsurf, eventName: agentActionName,
            project: nil, message: nil, timestamp: now
        )
    }
}

/// Decodes a hook's stdin payload into an `AgentEvent`, choosing the field
/// convention by agent kind. opencode sends explicit flags instead of stdin.
public enum HookPayload {
    public static func event(forAgent kind: AgentKind, stdin data: Data, now: Date) -> AgentEvent? {
        switch kind {
        case .cursor:
            return CursorHookPayload.decode(from: data)?.makeEvent(now: now)
        case .windsurf:
            return WindsurfHookPayload.decode(from: data)?.makeEvent(now: now)
        case .antigravity:
            return AntigravityHookPayload.decode(from: data)?.makeEvent(now: now)
        default:
            return ClaudeHookPayload.decode(from: data)?.makeEvent(now: now, kind: kind)
        }
    }
}
