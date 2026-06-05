import Foundation

/// Extracts a human-readable conversation title from an agent transcript file.
///
/// For Claude Code the transcript is a JSONL file. Each line is a JSON object.
/// The reader looks for:
/// 1. A `{"type":"summary","summary":"..."}` event — Claude names conversations
///    with this after the first exchange.
/// 2. Fallback: the first `{"type":"user","message":{"content":[{"type":"text","text":"..."}]}}`
///    line, truncated to 60 characters.
///
/// Results are cached per path so repeated calls within the same run are free.
public enum TranscriptReader {

    nonisolated(unsafe) private static var cache: [String: String] = [:]

    /// Returns the title for the transcript at `path`, or `nil` if unreadable.
    public static func title(at path: String) -> String? {
        if let hit = cache[path] { return hit }
        guard let result = read(path) else { return nil }
        cache[path] = result
        return result
    }

    /// Constructs the expected transcript path for a Claude Code session.
    ///
    /// Claude Code stores transcripts at `~/.claude/projects/<sanitized-cwd>/<session-id>.jsonl`
    /// where the sanitized CWD replaces every `/` with `-` and prepends a leading `-`.
    /// Use this when `transcript_path` is absent from the hook payload.
    public static func inferredPath(sessionId: String, cwd: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sanitized = "-" + cwd.replacingOccurrences(of: "/", with: "-")
        return "\(home)/.claude/projects/\(sanitized)/\(sessionId).jsonl"
    }

    private static func read(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        // Read first 32 KB — enough to cover the summary event which appears early.
        let raw = handle.readData(ofLength: 32_768)
        guard let text = String(data: raw, encoding: .utf8) else { return nil }

        var firstUserText: String?

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String
            else { continue }

            // Claude Code writes a "summary" event when it names the conversation.
            if type == "summary",
               let summary = json["summary"] as? String,
               !summary.trimmingCharacters(in: .whitespaces).isEmpty {
                return summary
            }

            // Capture the first user text as a fallback title.
            if firstUserText == nil, type == "user" {
                firstUserText = extractUserText(from: json)
            }
        }

        return firstUserText
    }

    private static func extractUserText(from json: [String: Any]) -> String? {
        // Claude Code format: message.content is an array of content blocks.
        if let message = json["message"] as? [String: Any],
           let contentBlocks = message["content"] as? [[String: Any]] {
            let text = contentBlocks
                .compactMap { $0["text"] as? String }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return String(text.prefix(60))
            }
        }
        // Older / simpler format: content is a plain string.
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? String,
           !content.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(content.prefix(60))
        }
        return nil
    }
}
