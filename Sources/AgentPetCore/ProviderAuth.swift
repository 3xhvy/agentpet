import Foundation

public struct ProviderAuthInfo: Identifiable, Sendable, Equatable {
    public let kind: AgentKind
    public let displayName: String
    public let credentialLabel: String
    public let note: String
    public let supportsQuota: Bool
    public let needsProjectId: Bool
    public let loginCommand: String?

    public var id: String { kind.rawValue }

    public init(
        kind: AgentKind,
        displayName: String,
        credentialLabel: String,
        note: String,
        supportsQuota: Bool,
        needsProjectId: Bool = false,
        loginCommand: String? = nil
    ) {
        self.kind = kind
        self.displayName = displayName
        self.credentialLabel = credentialLabel
        self.note = note
        self.supportsQuota = supportsQuota
        self.needsProjectId = needsProjectId
        self.loginCommand = loginCommand
    }
}

public enum ProviderAuthCatalog {
    public static let quotaProviders: [ProviderAuthInfo] = [
        ProviderAuthInfo(
            kind: .claude,
            displayName: "Claude",
            credentialLabel: "OAuth access token",
            note: "Detected from Claude Code OAuth files after you sign in with Claude Code.",
            supportsQuota: true,
            loginCommand: "claude"
        ),
        ProviderAuthInfo(
            kind: .codex,
            displayName: "Codex",
            credentialLabel: "ChatGPT access token",
            note: "Detected from ~/.codex/auth.json after you sign in with Codex.",
            supportsQuota: true,
            loginCommand: "codex login"
        ),
        ProviderAuthInfo(
            kind: .gemini,
            displayName: "Gemini",
            credentialLabel: "Google OAuth access token",
            note: "Detected from Gemini CLI OAuth files after you sign in with Gemini CLI.",
            supportsQuota: true,
            needsProjectId: true,
            loginCommand: "gemini auth login"
        ),
        ProviderAuthInfo(
            kind: .cursor,
            displayName: "Cursor",
            credentialLabel: "API key or token",
            note: "Detected from Cursor's local state database when Cursor is signed in.",
            supportsQuota: true
        ),
    ]

    public static func provider(for kind: AgentKind) -> ProviderAuthInfo? {
        quotaProviders.first { $0.kind == kind }
    }
}
