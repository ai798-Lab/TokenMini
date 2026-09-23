import XCTest
@testable import MacPulse

final class MultiSelectFilterTests: XCTestCase {
    func testModelChoicesFollowToolsWithoutChangingTotalsOrGlobalTools() {
        let now = Date()
        func event(_ tool: ToolKind, _ model: String) -> PricedEvent {
            PricedEvent(timestamp: now.addingTimeInterval(-1), tool: tool, model: model,
                        project: "demo", session: "s", input: 1, output: 1,
                        cacheWrite: 0, cacheRead: 0, cost: CostBreakdown(input: 1),
                        cacheSavedUSD: 0, isPriced: true)
        }
        let data = UsageAggregator.run([event(.claude, "claude-opus-5-5"), event(.codex, "gpt-6-sol")],
                                      filter: UsageFilter(time: .today, tools: [.claude]),
                                      now: now, calendar: .current)
        XCTAssertEqual(data.facets.models, ["claude-opus-5-5"])
        XCTAssertEqual(Set(data.facets.tools), [.claude, .codex])
        XCTAssertEqual(data.overview.eventCount, 1)
        XCTAssertEqual(data.overview.totalCostUSD, 1)
    }
}
