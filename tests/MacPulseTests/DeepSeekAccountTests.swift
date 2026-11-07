import XCTest
@testable import MacPulse

final class DeepSeekAccountTests: XCTestCase {
    func testMissingOrMalformedBalanceNeverBecomesZero() throws {
        for json in ["{}", #"{"is_available":true,"balance_infos":[]}"#,
                     #"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"NaN"}]}"#] {
            XCTAssertThrowsError(try DeepSeekAccountReader.parseBalance(Data(json.utf8)))
        }
        let response = try DeepSeekAccountReader.parseBalance(Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"12.3456"}]}"#.utf8))
        XCTAssertEqual(response.amounts.first?.display, "CNY 12.3456")
    }
    func testOnlyExplicitAPIKeyIsReadFromCredentialFile() {
        let fixture = "sk-unit-test-placeholder-123456"
        XCTAssertEqual(DeepSeekAccountReader.credential(inYAML: "version: 1\nrefs:\n  DEEPSEEK_API_KEY: '\(fixture)'\nrecords:\n  secret: ignored"), fixture)
        XCTAssertNil(DeepSeekAccountReader.credential(inYAML: "records:\n  DEEPSEEK_API_KEY: \(fixture)"))
        XCTAssertNil(DeepSeekAccountReader.credential(inYAML: "refs:\n  DEEPSEEK_API_KEY: grant-id"))
    }
    func testLiveReadOnlyAccountWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["TOKENMINI_DEEPSEEK_LIVE_TEST"] == "1" else { throw XCTSkip("Explicit account check only") }
        let key = try DeepSeekAccountReader.credential()
        let balance = try await DeepSeekAccountReader.fetchBalance(key: key)
        let models = try await DeepSeekAccountReader.fetchModels(key: key)
        XCTAssertFalse(balance.amounts.isEmpty)
        XCTAssertFalse(models.isEmpty)
        print("DEEPSEEK_VERIFIED currencies=\(balance.amounts.map(\.currency).joined(separator: ",")) models=\(models.joined(separator: ","))")
    }
}
