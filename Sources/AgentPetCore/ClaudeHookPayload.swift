import Foundation

/// The JSON Claude Code writes to a hook's stdin. Only the fields AgentPet
/// needs are decoded; the rest are ignored.
public struct ClaudeHookPayload: Decodable, Equatable {
    public let sessionId: String?
    public let cwd: String?
    public let hookEventName: String?
    public let message: String?
    public let toolName: String?
    public let toolInput: ClaudeToolInput?
    public let contextPercentage: Double?
    /// Absolute path to the conversation's JSONL transcript file.
    public let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
        case message
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case contextSizePercentage = "context_size_percentage"
        case contextPercentage = "context_percentage"
        case contextPercent = "context_percent"
        case contextUsagePercentage = "context_usage_percentage"
        case transcriptPath = "transcript_path"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        hookEventName = try c.decodeIfPresent(String.self, forKey: .hookEventName)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        toolInput = try c.decodeIfPresent(ClaudeToolInput.self, forKey: .toolInput)
        transcriptPath = try c.decodeIfPresent(String.self, forKey: .transcriptPath)
        contextPercentage =
            Self.decodePercent(from: c, forKey: .contextSizePercentage)
            ?? Self.decodePercent(from: c, forKey: .contextPercentage)
            ?? Self.decodePercent(from: c, forKey: .contextPercent)
            ?? Self.decodePercent(from: c, forKey: .contextUsagePercentage)
    }

    public static func decode(from data: Data) -> ClaudeHookPayload? {
        try? JSONDecoder().decode(ClaudeHookPayload.self, from: data)
    }

    /// Builds an `AgentEvent` from the payload, or `nil` if the essential
    /// fields (session id and event name) are missing.
    public func makeEvent(now: Date, kind: AgentKind = .claude) -> AgentEvent? {
        guard let sessionId, let hookEventName else { return nil }
        let context = ClaudeActivityFormatter.activityMessage(
            eventName: hookEventName,
            sessionId: sessionId,
            toolName: toolName,
            toolInput: toolInput,
            explicitMessage: message
        ) ?? toolName.map { "Using \($0)" }
        return AgentEvent(
            sessionId: sessionId, agentKind: kind, eventName: hookEventName,
            project: cwd,
            message: context,
            contextPercentage: contextPercentage,
            transcriptPath: transcriptPath,
            timestamp: now
        )
    }

    private static func decodePercent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}
