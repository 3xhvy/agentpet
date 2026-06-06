import Foundation
import Security
import AgentPetCore

@MainActor
final class QuotaController: ObservableObject {
    static let shared = QuotaController()

    @Published private(set) var snapshots: [QuotaSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published var warningEnabled: Bool {
        didSet {
            UserDefaults.standard.set(warningEnabled, forKey: Self.warningEnabledKey)
        }
    }
    @Published var warningThreshold: Double {
        didSet {
            warningThreshold = min(max(warningThreshold, 1), 95)
            UserDefaults.standard.set(warningThreshold, forKey: Self.warningThresholdKey)
            deliveredWarningKeys.removeAll()
        }
    }

    private var refreshTimer: Timer?
    private let service = QuotaService()
    private var deliveredWarningKeys: Set<String> = []

    private static let warningEnabledKey = "agentpet.quotaWarning.enabled"
    private static let warningThresholdKey = "agentpet.quotaWarning.threshold"

    init() {
        warningEnabled = (UserDefaults.standard.object(forKey: Self.warningEnabledKey) as? Bool) ?? true
        warningThreshold = UserDefaults.standard.object(forKey: Self.warningThresholdKey) as? Double ?? 20
    }

    func start() {
        refreshTimer?.invalidate()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let result = await service.fetchAll()
            snapshots = result
            isRefreshing = false
            handleQuotaWarnings(result)
        }
    }

    private func handleQuotaWarnings(_ snapshots: [QuotaSnapshot]) {
        guard warningEnabled else { return }
        let events = QuotaWarning.events(in: snapshots, thresholdRemainingPercentage: warningThreshold)
        for event in events {
            let key = warningKey(for: event)
            guard !deliveredWarningKeys.contains(key) else { continue }
            deliveredWarningKeys.insert(key)
            NotificationManager.shared.notify(
                title: "\(event.providerName) quota low",
                body: event.message
            )
            PetController.shared.showQuotaWarning(event)
        }
    }

    private func warningKey(for event: QuotaWarningEvent) -> String {
        let reset = event.resetAt.map { String(Int($0.timeIntervalSince1970)) } ?? "no-reset"
        return "\(event.provider.rawValue)|\(event.bucketName)|\(reset)"
    }
}

private struct QuotaCredential {
    var accessToken: String
    var refreshToken: String?
    var projectId: String?
}

private struct QuotaService {
    func fetchAll() async -> [QuotaSnapshot] {
        async let claude = fetchClaude()
        async let codex = fetchCodex()
        async let gemini = fetchGemini()
        let base = await [claude, codex, gemini]
        let cursor = await fetchCursor()
        let all = base + (cursor.map { [$0] } ?? [])
        return all.filter { QuotaCredentialStore.isConnected($0.provider) }
    }

    private func fetchClaude() async -> QuotaSnapshot {
        guard let credential = QuotaCredentialStore.claude() else {
            return QuotaParser.unavailable(
                provider: .claude,
                displayName: "Claude",
                message: "Connect Claude OAuth"
            )
        }

        do {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.httpMethod = "GET"
            request.timeoutInterval = 12
            request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let data = try await data(for: request)
            return try QuotaParser.claudeSnapshot(from: data)
        } catch {
            return QuotaParser.unavailable(
                provider: .claude,
                displayName: "Claude",
                message: "Quota unavailable"
            )
        }
    }

    private func fetchCodex() async -> QuotaSnapshot {
        guard let credential = QuotaCredentialStore.codex() else {
            return QuotaParser.unavailable(
                provider: .codex,
                displayName: "Codex",
                message: "No Codex auth"
            )
        }

        do {
            var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.httpMethod = "GET"
            request.timeoutInterval = 12
            request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let data = try await data(for: request)
            return try QuotaParser.codexSnapshot(from: data)
        } catch {
            return QuotaParser.unavailable(
                provider: .codex,
                displayName: "Codex",
                message: "Quota unavailable"
            )
        }
    }

    private func fetchGemini() async -> QuotaSnapshot {
        guard let credential = QuotaCredentialStore.gemini() else {
            return QuotaParser.unavailable(
                provider: .gemini,
                displayName: "Gemini",
                message: "No Gemini auth"
            )
        }

        do {
            let projectId = try await resolveGeminiProjectId(credential: credential)
            var request = URLRequest(url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["project": projectId])
            let data = try await data(for: request)
            return try QuotaParser.geminiSnapshot(from: data, plan: "Gemini CLI")
        } catch {
            return QuotaParser.unavailable(
                provider: .gemini,
                displayName: "Gemini",
                message: "Quota unavailable"
            )
        }
    }

    private func fetchCursor() async -> QuotaSnapshot? {
        guard let credential = QuotaCredentialStore.cursor() else { return nil }

        do {
            let dashboard = try await cursorPOST(
                "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
                token: credential.accessToken
            )
            let plan = try? await cursorPOST(
                "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo",
                token: credential.accessToken
            )
            let auth = try? await cursorGET(
                "https://api2.cursor.sh/auth/usage",
                token: credential.accessToken
            )
            return try QuotaParser.cursorSnapshot(dashboard: dashboard, auth: auth, plan: plan)
        } catch {
            return QuotaParser.unavailable(
                provider: .cursor,
                displayName: "Cursor",
                message: "Quota unavailable"
            )
        }
    }

    private func cursorGET(_ urlString: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await data(for: request)
    }

    private func cursorPOST(_ urlString: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        return try await data(for: request)
    }

    private func resolveGeminiProjectId(credential: QuotaCredential) async throws -> String {
        if let projectId = credential.projectId, !projectId.isEmpty { return projectId }

        var request = URLRequest(url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let data = try await data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.invalidResponse
        }
        if let project = json["cloudaicompanionProject"] as? String, !project.isEmpty {
            return project
        }
        if let project = json["cloudaicompanionProject"] as? [String: Any],
           let id = project["id"] as? String,
           !id.isEmpty {
            return id
        }
        throw QuotaError.missingProject
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw QuotaError.invalidResponse
        }
        return data
    }
}

private enum QuotaError: Error {
    case invalidResponse
    case missingProject
}

private enum QuotaCredentialStore {
    static func isConnected(_ kind: AgentKind) -> Bool {
        switch kind {
        case .claude:  return claude() != nil
        case .codex:   return codex() != nil
        case .gemini:  return gemini() != nil
        case .cursor:  return cursorAvailable()
        default:       return false
        }
    }

    static func cursorAvailable() -> Bool {
        cursor() != nil
    }

    static func cursor() -> QuotaCredential? {
        guard let dbPath = cursorDatabasePath(),
              let token = cursorSQLiteValue(dbPath: dbPath, key: "cursorAuth/accessToken")
                ?? cursorSQLiteValue(dbPath: dbPath, key: "cursorAuth/token") else {
            return nil
        }
        return QuotaCredential(accessToken: token)
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

    private static func cursorSQLiteValue(dbPath: String, key: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            dbPath,
            "SELECT value FROM itemTable WHERE key='\(key.replacingOccurrences(of: "'", with: "''"))' LIMIT 1;",
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
        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        if let data = raw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? String {
            let normalized = parsed.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        }
        return raw
    }

    static func claude() -> QuotaCredential? {
        if let token = env("ANTHROPIC_AUTH_TOKEN") ?? env("CLAUDE_CODE_OAUTH_TOKEN") {
            return QuotaCredential(accessToken: token)
        }
        if let token = claudeKeychainToken() {
            return QuotaCredential(accessToken: token)
        }
        for path in [
            "~/.claude/.credentials.json",
            "~/.claude/credentials.json",
            "~/.config/claude/credentials.json",
        ] {
            if let token = tokenFromJSON(path: expanded(path), keys: ["access_token", "accessToken", "oauth_access_token"]) {
                return QuotaCredential(accessToken: token)
            }
        }
        return nil
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

    static func codex() -> QuotaCredential? {
        let path = expanded("~/.codex/auth.json")
        guard let json = readJSON(path) else {
            if let token = env("OPENAI_ACCESS_TOKEN") { return QuotaCredential(accessToken: token) }
            return nil
        }
        let token = nestedString(json, path: ["tokens", "access_token"])
            ?? nestedString(json, path: ["access_token"])
            ?? env("OPENAI_ACCESS_TOKEN")
        guard let token else { return nil }
        let refresh = nestedString(json, path: ["tokens", "refresh_token"])
            ?? nestedString(json, path: ["refresh_token"])
        return QuotaCredential(accessToken: token, refreshToken: refresh)
    }

    static func gemini() -> QuotaCredential? {
        for path in [
            "~/.gemini/oauth_creds.json",
            "~/.config/gemini/oauth_creds.json",
        ] {
            guard let json = readJSON(expanded(path)) else { continue }
            let token = nestedString(json, path: ["access_token"])
                ?? nestedString(json, path: ["accessToken"])
                ?? nestedString(json, path: ["tokens", "access_token"])
            guard let token else { continue }
            let refresh = nestedString(json, path: ["refresh_token"])
                ?? nestedString(json, path: ["refreshToken"])
                ?? nestedString(json, path: ["tokens", "refresh_token"])
            let project = nestedString(json, path: ["project_id"])
                ?? nestedString(json, path: ["projectId"])
                ?? nestedString(json, path: ["cloudaicompanionProject"])
                ?? nestedString(json, path: ["cloudaicompanionProject", "id"])
            return QuotaCredential(accessToken: token, refreshToken: refresh, projectId: project)
        }
        guard let token = env("GEMINI_ACCESS_TOKEN") ?? env("GOOGLE_OAUTH_ACCESS_TOKEN") else { return nil }
        return QuotaCredential(accessToken: token, projectId: env("GEMINI_PROJECT_ID") ?? env("GOOGLE_CLOUD_PROJECT"))
    }

    private static func env(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func savedProjectId(for kind: AgentKind) -> String? {
        let key = "agentpet.providerAuth.project.\(kind.rawValue)"
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func tokenFromJSON(path: String, keys: [String]) -> String? {
        guard let json = readJSON(path) else { return nil }
        for key in keys {
            if let value = nestedString(json, path: [key]) { return value }
            if let value = nestedString(json, path: ["tokens", key]) { return value }
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
}
