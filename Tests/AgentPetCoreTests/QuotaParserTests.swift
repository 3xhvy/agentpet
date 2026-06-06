import XCTest
@testable import AgentPetCore

final class QuotaParserTests: XCTestCase {
    func testParsesClaudeOAuthUsageWindows() throws {
        let data = Data("""
        {
          "five_hour": {"utilization": 42, "resets_at": "2026-06-06T12:00:00Z"},
          "seven_day": {"utilization": 64, "resets_at": "2026-06-08T00:00:00Z"},
          "seven_day_sonnet": {"utilization": 75, "resets_at": "2026-06-08T00:00:00Z"}
        }
        """.utf8)

        let snapshot = try QuotaParser.claudeSnapshot(from: data, fetchedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.plan, "Claude Code")
        XCTAssertEqual(snapshot.buckets.map(\.name), ["session (5h)", "weekly (7d)", "weekly sonnet (7d)"])
        XCTAssertEqual(snapshot.buckets[0].used, 42)
        XCTAssertEqual(snapshot.buckets[0].total, 100)
        XCTAssertEqual(snapshot.buckets[0].remainingPercentage, 58)
    }

    func testParsesCodexUsageWindows() throws {
        let data = Data("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {"used_percent": 30, "reset_at": 1780754400},
            "secondary_window": {"percent_used": 70, "resets_at": "2026-06-09T00:00:00Z"}
          },
          "code_review_rate_limit": {
            "rate_limit": {
              "primary": {"used_percent": 15, "reset_at": "2026-06-06T12:00:00Z"}
            }
          }
        }
        """.utf8)

        let snapshot = try QuotaParser.codexSnapshot(from: data, fetchedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.plan, "plus")
        XCTAssertEqual(snapshot.buckets.map(\.name), ["session", "weekly", "review_session"])
        XCTAssertEqual(snapshot.buckets[0].remainingPercentage, 70)
        XCTAssertEqual(snapshot.buckets[1].remainingPercentage, 30)
    }

    func testParsesGeminiQuotaBuckets() throws {
        let data = Data("""
        {
          "buckets": [
            {"modelId": "gemini-3-flash-preview", "remainingFraction": 0.75, "resetTime": "2026-06-06T12:00:00Z"},
            {"modelId": "gemini-3-pro-preview", "remainingFraction": 0.2, "resetTime": "2026-06-06T13:00:00Z"}
          ]
        }
        """.utf8)

        let snapshot = try QuotaParser.geminiSnapshot(from: data, plan: "Free", fetchedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.provider, .gemini)
        XCTAssertEqual(snapshot.plan, "Free")
        XCTAssertEqual(snapshot.buckets[0].name, "gemini-3-flash-preview")
        XCTAssertEqual(snapshot.buckets[0].used, 250)
        XCTAssertEqual(snapshot.buckets[0].total, 1000)
        XCTAssertEqual(snapshot.buckets[0].remainingPercentage, 75)
        XCTAssertEqual(snapshot.buckets[1].remainingPercentage, 20)
    }

    func testParsesCursorIncludedSpendNotTotalSpend() throws {
        let dashboard = Data("""
        {
          "billingCycleEnd": "1782283410000",
          "planUsage": {
            "totalSpend": 19146,
            "includedSpend": 2000,
            "bonusSpend": 17146,
            "limit": 2000,
            "autoPercentUsed": 97.34,
            "apiPercentUsed": 100,
            "totalPercentUsed": 98.18
          }
        }
        """.utf8)
        let plan = Data("""
        {"planInfo":{"planName":"Pro","includedAmountCents":2000}}
        """.utf8)

        let snapshot = try QuotaParser.cursorSnapshot(
            dashboard: dashboard,
            plan: plan,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(snapshot.provider, .cursor)
        XCTAssertEqual(snapshot.plan, "Pro")
        XCTAssertEqual(snapshot.buckets.first?.name, "included")
        XCTAssertEqual(snapshot.buckets.first?.used, 2000)
        XCTAssertEqual(snapshot.buckets.first?.total, 2000)
        XCTAssertEqual(snapshot.buckets.first?.remainingPercentage, 0)
        XCTAssertEqual(snapshot.buckets.first(where: { $0.name == "api" })?.remainingPercentage, 0)
    }

    func testParsesCursorAuthUsageFallback() throws {
        let dashboard = Data("{}".utf8)
        let auth = Data("""
        {
          "gpt-4": {"numRequests": 150, "maxRequestUsage": 500},
          "startOfMonth": "2026-03-01T00:00:00.000Z"
        }
        """.utf8)

        let snapshot = try QuotaParser.cursorSnapshot(dashboard: dashboard, auth: auth)

        XCTAssertEqual(snapshot.buckets.count, 1)
        XCTAssertEqual(snapshot.buckets[0].name, "gpt-4")
        XCTAssertEqual(snapshot.buckets[0].remainingPercentage, 70)
    }
}
