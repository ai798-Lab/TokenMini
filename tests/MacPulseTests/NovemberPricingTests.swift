import XCTest
@testable import MacPulse

final class NovemberPricingTests: XCTestCase {
    func testCurrentModelAliasesRetainMeteringAndHaveVerifiedPrices() throws {
        for (id, input, output, read) in [
            ("gpt-6.1-sol", 2.0, 10.0, 0.1),
            ("gpt-6.1-terra", 1.0, 5.0, 0.05),
            ("claude-sonnet-5-5", 2.0, 10.0, 0.1),
            ("claude-haiku-5-5", 0.1, 0.5, 0.01),
            ("deepseek-flash", 0.3, 1.2, 0.006),
            ("deepseek-v4.1-flash-1017", 0.3, 1.2, 0.006),
            ("kimi-code/k3.1-pro", 2.0, 10.0, 0.2),
            ("kimi-code/k3.1-pro-highspeed", 4.0, 20.0, 0.2)
        ] {
            let pricing = try XCTUnwrap(PricingTable.pricing(for: id), id)
            XCTAssertEqual(pricing.inputPerMTok, input)
            XCTAssertEqual(pricing.outputPerMTok, output)
            XCTAssertEqual(pricing.cacheReadPerMTok, read)
        }
    }
    func testUnknownInternalModelKeepsTokensWithoutInventingPrice() {
        XCTAssertNil(PricingTable.pricing(for: "codex-auto-review"))
    }
}
