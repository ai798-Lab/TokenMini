import XCTest
@testable import MacPulse

final class ClaudeQuotaConsentTests: XCTestCase {
    @MainActor
    func testDefaultAndLegacyEnabledRequireConsent() async {
        let name = "TokenMiniConsentTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let fresh = QuotaStore(defaults: defaults, confirmClaudeAccess: { XCTFail("Must not prompt at startup"); return false }, fetchClaude: { _ in XCTFail("Must not access credentials"); return nil })
        XCTAssertFalse(fresh.claudeAccessEnabled)
        defaults.set(true, forKey: "macpulse.claudeQuotaAccessEnabled")
        let legacy = QuotaStore(defaults: defaults, confirmClaudeAccess: { XCTFail("Must not prompt at startup"); return false }, fetchClaude: { _ in XCTFail("Must not access credentials"); return nil })
        XCTAssertFalse(legacy.claudeAccessEnabled)
        XCTAssertFalse(defaults.bool(forKey: "macpulse.claudeQuotaAccessEnabled"))
    }

    @MainActor
    func testCancelDoesNotEnablePersistOrFetch() async {
        let name = "TokenMiniConsentTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var prompts = 0
        let store = QuotaStore(defaults: defaults, confirmClaudeAccess: { prompts += 1; return false }, fetchClaude: { _ in XCTFail("Cancelled consent must not fetch"); return nil })
        store.setClaudeAccessEnabled(true)
        await Task.yield()
        XCTAssertEqual(prompts, 1)
        XCTAssertFalse(store.claudeAccessEnabled)
        XCTAssertFalse(defaults.bool(forKey: "macpulse.claudeQuotaAccessEnabled"))
    }

    @MainActor
    func testConfirmPersistsAndReenableRequiresFreshConsent() async {
        let name = "TokenMiniConsentTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var prompts = 0
        var allow = true
        let fetched = expectation(description: "Fetch only after consent")
        let store = QuotaStore(defaults: defaults, confirmClaudeAccess: { prompts += 1; return allow }, fetchClaude: { mode in
            guard case .userInitiated = mode else { XCTFail("Expected explicit activation"); return nil }
            fetched.fulfill()
            return nil
        })
        store.setClaudeAccessEnabled(true)
        XCTAssertTrue(store.claudeAccessEnabled)
        XCTAssertTrue(defaults.bool(forKey: "macpulse.claudeQuotaAccessEnabled"))
        await fulfillment(of: [fetched], timeout: 2)
        let restarted = QuotaStore(defaults: defaults, confirmClaudeAccess: { XCTFail("Previously confirmed preference may persist"); return false }, fetchClaude: { _ in nil })
        XCTAssertTrue(restarted.claudeAccessEnabled)
        store.setClaudeAccessEnabled(false)
        XCTAssertFalse(store.claudeAccessEnabled)
        XCTAssertEqual(prompts, 1)
        allow = false
        store.setClaudeAccessEnabled(true)
        XCTAssertEqual(prompts, 2)
        XCTAssertFalse(store.claudeAccessEnabled)
        XCTAssertFalse(defaults.bool(forKey: "macpulse.claudeQuotaAccessEnabled"))
    }
}
