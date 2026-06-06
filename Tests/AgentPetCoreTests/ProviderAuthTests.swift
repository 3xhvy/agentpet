import XCTest
@testable import AgentPetCore

final class ProviderAuthTests: XCTestCase {
    func testQuotaAuthProvidersAreListedInDisplayOrder() {
        XCTAssertEqual(
            ProviderAuthCatalog.quotaProviders.map(\.kind),
            [.claude, .codex, .gemini, .cursor]
        )
    }

    func testProviderMetadataDescribesQuotaSupport() {
        let claude = ProviderAuthCatalog.provider(for: .claude)
        XCTAssertEqual(claude?.displayName, "Claude")
        XCTAssertTrue(claude?.supportsQuota == true)

        let cursor = ProviderAuthCatalog.provider(for: .cursor)
        XCTAssertEqual(cursor?.displayName, "Cursor")
        XCTAssertTrue(cursor?.supportsQuota == true)
    }
}
