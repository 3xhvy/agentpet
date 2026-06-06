import Foundation

public struct QuotaBucket: Identifiable, Codable, Sendable, Equatable {
    public var id: String { name }
    public var name: String
    public var used: Double
    public var total: Double
    public var remainingPercentage: Double
    public var resetAt: Date?
    public var unlimited: Bool

    public init(
        name: String,
        used: Double,
        total: Double,
        remainingPercentage: Double,
        resetAt: Date? = nil,
        unlimited: Bool = false
    ) {
        self.name = name
        self.used = used
        self.total = total
        self.remainingPercentage = min(max(remainingPercentage, 0), 100)
        self.resetAt = resetAt
        self.unlimited = unlimited
    }
}

public struct QuotaSnapshot: Identifiable, Codable, Sendable, Equatable {
    public var id: String { provider.rawValue }
    public var provider: AgentKind
    public var displayName: String
    public var plan: String?
    public var buckets: [QuotaBucket]
    public var message: String?
    public var fetchedAt: Date

    public init(
        provider: AgentKind,
        displayName: String,
        plan: String? = nil,
        buckets: [QuotaBucket] = [],
        message: String? = nil,
        fetchedAt: Date
    ) {
        self.provider = provider
        self.displayName = displayName
        self.plan = plan
        self.buckets = buckets
        self.message = message
        self.fetchedAt = fetchedAt
    }
}

public enum QuotaParser {
    public enum ParseError: Error {
        case invalidJSON
    }

    public static func claudeSnapshot(from data: Data, fetchedAt: Date = Date()) throws -> QuotaSnapshot {
        let json = try object(from: data)
        var buckets: [QuotaBucket] = []

        func appendWindow(_ key: String, name: String) {
            guard let window = json[key] as? [String: Any],
                  let used = number(window["utilization"]) else { return }
            buckets.append(
                QuotaBucket(
                    name: name,
                    used: used,
                    total: 100,
                    remainingPercentage: 100 - used,
                    resetAt: parseDate(window["resets_at"])
                )
            )
        }

        appendWindow("five_hour", name: "session (5h)")
        appendWindow("seven_day", name: "weekly (7d)")

        for key in json.keys.sorted() where key.hasPrefix("seven_day_") && key != "seven_day" {
            let model = key.replacingOccurrences(of: "seven_day_", with: "")
            appendWindow(key, name: "weekly \(model) (7d)")
        }

        return QuotaSnapshot(
            provider: .claude,
            displayName: "Claude",
            plan: "Claude Code",
            buckets: buckets,
            fetchedAt: fetchedAt
        )
    }

    public static func codexSnapshot(from data: Data, fetchedAt: Date = Date()) throws -> QuotaSnapshot {
        let json = try object(from: data)
        let plan = string(json["plan_type"]) ?? (json["summary"] as? [String: Any]).flatMap { string($0["plan"]) }
        var buckets: [QuotaBucket] = []

        let normal = (json["rate_limit"] as? [String: Any])
            ?? (json["rate_limits"] as? [String: Any])
            ?? ((json["rate_limits_by_limit_id"] as? [String: Any])?["codex"] as? [String: Any])
        appendCodexWindows(from: normal, prefix: nil, into: &buckets)

        let review = (json["code_review_rate_limit"] as? [String: Any])
            ?? (json["review_rate_limit"] as? [String: Any])
            ?? reviewRateLimit(from: json)
        appendCodexWindows(from: review, prefix: "review", into: &buckets)

        return QuotaSnapshot(
            provider: .codex,
            displayName: "Codex",
            plan: plan,
            buckets: buckets,
            fetchedAt: fetchedAt
        )
    }

    public static func geminiSnapshot(from data: Data, plan: String? = nil, fetchedAt: Date = Date()) throws -> QuotaSnapshot {
        let json = try object(from: data)
        let buckets = (json["buckets"] as? [[String: Any]] ?? []).compactMap { bucket -> QuotaBucket? in
            guard let name = string(bucket["modelId"]),
                  let fraction = number(bucket["remainingFraction"]) else { return nil }
            let total: Double = 1000
            let remaining = min(max(fraction, 0), 1) * total
            return QuotaBucket(
                name: name,
                used: max(0, total - remaining),
                total: total,
                remainingPercentage: fraction * 100,
                resetAt: parseDate(bucket["resetTime"])
            )
        }

        return QuotaSnapshot(
            provider: .gemini,
            displayName: "Gemini",
            plan: plan,
            buckets: buckets,
            fetchedAt: fetchedAt
        )
    }

    public static func cursorSnapshot(
        dashboard data: Data,
        auth authData: Data? = nil,
        plan planData: Data? = nil,
        fetchedAt: Date = Date()
    ) throws -> QuotaSnapshot {
        let dashboard = try object(from: data)
        let planName = planData.flatMap { try? object(from: $0) }
            .flatMap { ($0["planInfo"] as? [String: Any]).flatMap { string($0["planName"]) } }

        var buckets: [QuotaBucket] = []
        let resetAt = parseCursorMillis(dashboard["billingCycleEnd"])

        if let planUsage = dashboard["planUsage"] as? [String: Any] {
            if let included = cursorIncludedBucket(planUsage, resetAt: resetAt) {
                buckets.append(included)
            }
            if let auto = cursorPercentBucket(planUsage, key: "autoPercentUsed", name: "auto") {
                buckets.append(auto)
            }
            if let api = cursorPercentBucket(planUsage, key: "apiPercentUsed", name: "api") {
                buckets.append(api)
            }
        }

        if buckets.isEmpty, let authData, let auth = try? object(from: authData) {
            buckets.append(contentsOf: cursorAuthBuckets(from: auth, resetAt: resetAt))
        }

        return QuotaSnapshot(
            provider: .cursor,
            displayName: "Cursor",
            plan: planName,
            buckets: buckets,
            message: buckets.isEmpty ? "Quota unavailable" : nil,
            fetchedAt: fetchedAt
        )
    }

    public static func unavailable(
        provider: AgentKind,
        displayName: String,
        message: String,
        fetchedAt: Date = Date()
    ) -> QuotaSnapshot {
        QuotaSnapshot(provider: provider, displayName: displayName, message: message, fetchedAt: fetchedAt)
    }

    /// Included plan allowance in cents. Uses `includedSpend`, not `totalSpend`
    /// (which includes bonus/provider credits and inflates usage).
    private static func cursorIncludedBucket(
        _ planUsage: [String: Any],
        resetAt: Date?
    ) -> QuotaBucket? {
        let limit = number(planUsage["limit"])
        let includedSpend = number(planUsage["includedSpend"])
        let remaining = number(planUsage["remaining"])
        let totalPercentUsed = number(planUsage["totalPercentUsed"])

        if let limit, limit > 0 {
            let used = includedSpend
                ?? remaining.map { max(0, limit - $0) }
                ?? totalPercentUsed.map { min(limit, limit * $0 / 100) }
            guard let used else { return nil }
            let remainingPct = remaining.map { ($0 / limit) * 100 }
                ?? max(0, ((limit - used) / limit) * 100)
            return QuotaBucket(
                name: "included",
                used: used,
                total: limit,
                remainingPercentage: remainingPct,
                resetAt: resetAt
            )
        }

        guard let totalPercentUsed else { return nil }
        return QuotaBucket(
            name: "usage",
            used: totalPercentUsed,
            total: 100,
            remainingPercentage: max(0, 100 - totalPercentUsed),
            resetAt: resetAt
        )
    }

    private static func cursorPercentBucket(
        _ planUsage: [String: Any],
        key: String,
        name: String
    ) -> QuotaBucket? {
        guard let used = number(planUsage[key]) else { return nil }
        return QuotaBucket(
            name: name,
            used: used,
            total: 100,
            remainingPercentage: max(0, 100 - used)
        )
    }

    private static func cursorAuthBuckets(from auth: [String: Any], resetAt: Date?) -> [QuotaBucket] {
        let preferred = ["gpt-4", "default", "premium"]
        var buckets: [QuotaBucket] = []
        for (key, value) in auth where key != "startOfMonth" {
            guard let model = value as? [String: Any] else { continue }
            let used = number(model["numRequests"]) ?? number(model["used"])
            let limit = number(model["maxRequestUsage"]) ?? number(model["limit"])
            guard let used, let limit, limit > 0 else { continue }
            buckets.append(
                QuotaBucket(
                    name: key,
                    used: used,
                    total: limit,
                    remainingPercentage: max(0, ((limit - used) / limit) * 100),
                    resetAt: resetAt
                )
            )
        }
        if buckets.isEmpty { return [] }
        for key in preferred {
            if let match = buckets.first(where: { $0.name == key }) { return [match] }
        }
        return [buckets[0]]
    }

    private static func parseCursorMillis(_ value: Any?) -> Date? {
        guard let ms = number(value) else { return parseDate(value) }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    private static func appendCodexWindows(from raw: [String: Any]?, prefix: String?, into buckets: inout [QuotaBucket]) {
        guard let raw else { return }
        let rateLimit = raw["rate_limit"] as? [String: Any] ?? raw
        let primary = (rateLimit["primary_window"] as? [String: Any])
            ?? (rateLimit["primary"] as? [String: Any])
            ?? (raw["primary_window"] as? [String: Any])
            ?? (raw["primary"] as? [String: Any])
        let secondary = (rateLimit["secondary_window"] as? [String: Any])
            ?? (rateLimit["secondary"] as? [String: Any])
            ?? (raw["secondary_window"] as? [String: Any])
            ?? (raw["secondary"] as? [String: Any])

        if let bucket = codexBucket(primary, name: prefix.map { "\($0)_session" } ?? "session") {
            buckets.append(bucket)
        }
        if let bucket = codexBucket(secondary, name: prefix.map { "\($0)_weekly" } ?? "weekly") {
            buckets.append(bucket)
        }
    }

    private static func codexBucket(_ window: [String: Any]?, name: String) -> QuotaBucket? {
        guard let window else { return nil }
        let used = number(window["used_percent"]) ?? number(window["percent_used"]) ?? 0
        return QuotaBucket(
            name: name,
            used: used,
            total: 100,
            remainingPercentage: 100 - used,
            resetAt: parseDate(window["reset_at"] ?? window["resets_at"] ?? window["resetAt"])
        )
    }

    private static func reviewRateLimit(from json: [String: Any]) -> [String: Any]? {
        if let byLimit = json["rate_limits_by_limit_id"] as? [String: Any] {
            for key in ["code_review", "codex_review", "review"] {
                if let match = byLimit[key] as? [String: Any] { return match }
            }
        }
        guard let additional = json["additional_rate_limits"] as? [[String: Any]] else { return nil }
        return additional.first { entry in
            let id = [
                string(entry["limit_name"]),
                string(entry["metered_feature"]),
                string(entry["id"]),
            ].compactMap { $0?.lowercased() }.joined(separator: " ")
            return id.contains("review")
        }
    }

    private static func object(from data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        return json
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let value = value as? Date { return value }
        if let value = number(value) {
            return Date(timeIntervalSince1970: value < 1_000_000_000_000 ? value : value / 1000)
        }
        guard let text = string(value) else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}
