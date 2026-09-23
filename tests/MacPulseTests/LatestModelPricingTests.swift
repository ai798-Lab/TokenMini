import XCTest
@testable import MacPulse

final class LatestModelPricingTests: XCTestCase {
    func testOpus55CachingAndFastPrices() throws {
        let p = try XCTUnwrap(PricingTable.pricing(for: "anthropic/claude-opus-5-5"))
        XCTAssertEqual(p.inputPerMTok, 4)
        XCTAssertEqual(p.outputPerMTok, 20)
        XCTAssertEqual(p.cacheReadPerMTok, 0.2)
        XCTAssertEqual(p.cacheWritePerMTok, 5)
        XCTAssertEqual(p.cacheWrite1hPerMTok, 8)
        XCTAssertEqual(PricingTable.fastMultiplier(for: "claude-opus-5-5"), 2)
        XCTAssertEqual(p.cost(input: 1_000_000, output: 1_000_000,
                              cacheWrite: 2_000_000, cacheWrite1h: 1_000_000,
                              cacheRead: 1_000_000), 37.2, accuracy: 0.000001)
    }

    func testGPT6SolAndLunaFullRequestThresholdIncludesCache() throws {
        for (model, input, output, read, write) in [
            ("gpt-6-sol", 2.0, 10.0, 0.2, 2.5),
            ("gpt-6-luna", 0.1, 0.5, 0.01, 0.125)
        ] {
            let p = try XCTUnwrap(PricingTable.pricing(for: model))
            XCTAssertEqual(p.inputPerMTok, input)
            XCTAssertEqual(p.outputPerMTok, output)
            XCTAssertEqual(p.cacheReadPerMTok, read)
            XCTAssertEqual(p.cacheWritePerMTok, write)
            XCTAssertEqual(PricingTable.fastMultiplier(for: model), 2)
            let at = p.breakdown(input: 2_000, output: 1000, cacheWrite: 0, cacheWrite1h: 0, cacheRead: 270_000)
            let over = p.breakdown(input: 2_001, output: 1000, cacheWrite: 0, cacheWrite1h: 0, cacheRead: 270_000)
            XCTAssertEqual(at.output, output * 0.001, accuracy: 0.000001)
            XCTAssertEqual(over.output, output * 0.0015, accuracy: 0.000001)
            XCTAssertEqual(over.cacheRead, read * 0.54, accuracy: 0.000001)
        }
        XCTAssertNil(PricingTable.pricing(for: "gpt-6-sol-unknown"))
        XCTAssertEqual(PricingTable.fastMultiplier(for: "claude-opus-4-80"), 1)
    }
}
