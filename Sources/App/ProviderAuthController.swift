import AppKit
import Foundation
import Security
import AgentPetCore

@MainActor
final class ProviderAuthController: ObservableObject {
    static let shared = ProviderAuthController()

    @Published private(set) var savedKinds: Set<AgentKind> = []
    @Published private(set) var localKinds: Set<AgentKind> = []
    @Published private(set) var accountKinds: Set<AgentKind> = []
    @Published private(set) var projectIds: [AgentKind: String] = [:]

    private let defaults = UserDefaults.standard
    private let projectPrefix = "agentpet.providerAuth.project."
    private let importedKey = "agentpet.providerAuth.importedKinds"

    init() {
        refresh()
    }

    func refresh() {
        localKinds = Set(ProviderAuthCatalog.quotaProviders.compactMap { provider in
            ProviderLocalAuth.isAvailable(provider.kind) ? provider.kind : nil
        })
        accountKinds = Set(ProviderAuthCatalog.quotaProviders.compactMap { provider in
            ProviderLocalAuth.hasSignedInAccount(provider.kind) ? provider.kind : nil
        })
        savedKinds = importedKinds().filter { localKinds.contains($0) || accountKinds.contains($0) }
        var projects: [AgentKind: String] = [:]
        for provider in ProviderAuthCatalog.quotaProviders where provider.needsProjectId {
            let key = projectPrefix + provider.kind.rawValue
            let saved = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let value = saved.isEmpty ? (ProviderLocalAuth.projectId(for: provider.kind) ?? "") : saved
            if !value.isEmpty { projects[provider.kind] = value }
        }
        projectIds = projects
    }

    func isConnected(_ kind: AgentKind) -> Bool {
        savedKinds.contains(kind) || localKinds.contains(kind) || accountKinds.contains(kind)
    }

    func connectionSource(for kind: AgentKind) -> String {
        if savedKinds.contains(kind) { return "Imported" }
        if localKinds.contains(kind) { return "CLI auth" }
        if accountKinds.contains(kind) { return "Signed in" }
        return "Not connected"
    }

    func projectId(for kind: AgentKind) -> String {
        projectIds[kind] ?? ""
    }

    func save(kind: AgentKind, token: String, projectId: String? = nil) {
        if let projectId {
            let key = projectPrefix + kind.rawValue
            let cleanProject = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanProject.isEmpty {
                defaults.removeObject(forKey: key)
            } else {
                defaults.set(cleanProject, forKey: key)
            }
        }
        refresh()
        QuotaController.shared.refresh()
    }

    func importLocal(kind: AgentKind) {
        guard let credential = ProviderLocalAuth.credential(for: kind) else {
            refresh()
            return
        }
        setImported(true, for: kind)
        if let projectId = credential.projectId {
            defaults.set(projectId, forKey: projectPrefix + kind.rawValue)
        }
        refresh()
        QuotaController.shared.refresh()
    }

    func clear(kind: AgentKind) {
        setImported(false, for: kind)
        defaults.removeObject(forKey: projectPrefix + kind.rawValue)
        refresh()
        QuotaController.shared.refresh()
    }

    func openLogin(for provider: ProviderAuthInfo) {
        guard let command = provider.loginCommand else { return }
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedAppleScript(command))"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private func escapedAppleScript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func importedKinds() -> Set<AgentKind> {
        Set((defaults.stringArray(forKey: importedKey) ?? []).compactMap(AgentKind.init(rawValue:)))
    }

    private func setImported(_ imported: Bool, for kind: AgentKind) {
        var kinds = importedKinds()
        if imported {
            kinds.insert(kind)
        } else {
            kinds.remove(kind)
        }
        defaults.set(kinds.map(\.rawValue).sorted(), forKey: importedKey)
    }
}

private struct ProviderLocalCredential {
    var accessToken: String
    var projectId: String?
}

private enum ProviderLocalAuth {
    static func isAvailable(_ kind: AgentKind) -> Bool {
        credential(for: kind) != nil
    }

    static func hasSignedInAccount(_ kind: AgentKind) -> Bool {
        switch kind {
        case .claude:
            guard let json = readJSON(expanded("~/.claude.json")),
                  let account = json["oauthAccount"] as? [String: Any] else { return false }
            return nestedString(account, path: ["accountUuid"]) != nil
                || nestedString(account, path: ["emailAddress"]) != nil
        case .cursor:
            return cursorDatabasePath() != nil
        default:
            return isAvailable(kind)
        }
    }

    static func projectId(for kind: AgentKind) -> String? {
        credential(for: kind)?.projectId
    }

    static func credential(for kind: AgentKind) -> ProviderLocalCredential? {
        switch kind {
        case .claude:
            if let token = claudeKeychainToken() {
                return ProviderLocalCredential(accessToken: token)
            }
            for path in [
                "~/.claude/.credentials.json",
                "~/.claude/credentials.json",
                "~/.config/claude/credentials.json",
            ] {
                if let json = readJSON(expanded(path)),
                   let token = string(json, ["access_token", "accessToken", "oauth_access_token"], nestedInTokens: true) {
                    return ProviderLocalCredential(accessToken: token)
                }
            }
            return nil
        case .codex:
            guard let json = readJSON(expanded("~/.codex/auth.json")),
                  let token = nestedString(json, path: ["tokens", "access_token"])
                    ?? nestedString(json, path: ["access_token"]) else {
                return nil
            }
            return ProviderLocalCredential(accessToken: token)
        case .gemini:
            for path in [
                "~/.gemini/oauth_creds.json",
                "~/.config/gemini/oauth_creds.json",
            ] {
                guard let json = readJSON(expanded(path)),
                      let token = nestedString(json, path: ["access_token"])
                        ?? nestedString(json, path: ["accessToken"])
                        ?? nestedString(json, path: ["tokens", "access_token"]) else { continue }
                let project = nestedString(json, path: ["project_id"])
                    ?? nestedString(json, path: ["projectId"])
                    ?? nestedString(json, path: ["cloudaicompanionProject"])
                    ?? nestedString(json, path: ["cloudaicompanionProject", "id"])
                return ProviderLocalCredential(accessToken: token, projectId: project)
            }
            return nil
        case .cursor:
            guard let dbPath = cursorDatabasePath(),
                  let token = cursorValue(dbPath: dbPath, keys: ["cursorAuth/accessToken", "cursorAuth/token"]) else {
                return nil
            }
            return ProviderLocalCredential(accessToken: token)
        default:
            return nil
        }
    }

    private static func cursorDatabasePath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in [
            "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            "\(home)/Library/Application Support/Cursor - Insiders/User/globalStorage/state.vscdb",
        ] where FileManager.default.isReadableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func cursorValue(dbPath: String, keys: [String]) -> String? {
        for key in keys {
            guard let raw = sqliteValue(dbPath: dbPath, key: key),
                  let normalized = normalizeCursorValue(raw),
                  !normalized.isEmpty else { continue }
            return normalized
        }
        return nil
    }

    private static func sqliteValue(dbPath: String, key: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            dbPath,
            "SELECT value FROM itemTable WHERE key='\(key.replacingOccurrences(of: "'", with: "''"))' LIMIT 1;"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func normalizeCursorValue(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let data = trimmed.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data),
           let text = parsed as? String {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        }
        return trimmed
    }

    private static func string(_ json: [String: Any], _ keys: [String], nestedInTokens: Bool) -> String? {
        for key in keys {
            if let value = nestedString(json, path: [key]) { return value }
            if nestedInTokens, let value = nestedString(json, path: ["tokens", key]) { return value }
        }
        return nil
    }

    private static func readJSON(_ path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func nestedString(_ json: [String: Any], path: [String]) -> String? {
        var value: Any? = json
        for key in path {
            value = (value as? [String: Any])?[key]
        }
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func expanded(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private static func claudeKeychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }
        return token
    }
}
