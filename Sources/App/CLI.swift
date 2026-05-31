import AgentPetCore
import Foundation

/// CLI helper invoked by agent hooks: `agentpet hook --event ... --session ...`.
enum HookCLI {
    static func run(arguments: [String]) -> Never {
        // Explicit flags win; otherwise fall back to a hook payload on stdin
        // (Claude/Codex/Gemini share the same field names). `--agent` selects
        // which agent's event names to map.
        let now = Date()
        let parsed = HookArguments.parse(arguments)
        let kind = parsed.agent.flatMap(AgentKind.init(rawValue:)) ?? .claude
        let event = parsed.makeEvent(now: now)
            ?? ClaudeHookPayload.decode(from: FileHandle.standardInput.readDataToEndOfFile())?.makeEvent(now: now, kind: kind)

        guard let event else {
            FileHandle.standardError.write(Data(
                "usage: agentpet hook --event <name> --session <id> [--project <path>] [--agent <kind>] [--message <text>]\n         or pipe a Claude Code hook JSON payload on stdin\n".utf8
            ))
            exit(2)
        }
        EventSender.send(event, socketPath: AgentPetPaths.socketPath, queueDir: AgentPetPaths.queueDir)
        exit(0)
    }
}
