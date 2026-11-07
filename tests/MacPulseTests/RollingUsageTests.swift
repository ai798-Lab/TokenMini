import Foundation
import XCTest
@testable import MacPulse

final class RollingUsageTests: XCTestCase {
    func testRollingCostIncludesYesterdayAcrossMidnightAndPreservesToday() {
        let midnight = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_790_294_400))
        let now = midnight.addingTimeInterval(30 * 60)
        let events = [event(at: midnight.addingTimeInterval(-30 * 60), cost: 2),
                      event(at: midnight.addingTimeInterval(10 * 60), cost: 3)]

        let result = UsageStore.aggregate(events: events, now: now)

        XCTAssertEqual(result.last24Hours.totalCostUSD, 5)
        XCTAssertEqual(result.last24Hours.totalTokens, 200)
        XCTAssertEqual(result.last24Hours.eventCount, 2)
        XCTAssertEqual(result.today.totalCostUSD, 3)
        XCTAssertEqual(result.today.eventCount, 1)
    }

    func testRollingWindowUsesExact24HoursAndMatchesDashboardBoundaries() {
        let now = Date(timeIntervalSince1970: 1_790_296_200)
        let cutoff = now.addingTimeInterval(-86_400)
        let events = [event(at: cutoff.addingTimeInterval(-0.001), cost: 100),
                      event(at: cutoff, cost: 2),
                      event(at: now.addingTimeInterval(-0.001), cost: 3),
                      event(at: now, cost: 200),
                      event(at: now.addingTimeInterval(1), cost: 400)]

        let result = UsageStore.aggregate(events: events, now: now).last24Hours
        let dashboard = UsageAggregator.run(events.map { PricedEvent.from($0) },
                                            filter: UsageFilter(time: .last24h),
                                            now: now, calendar: .current)

        XCTAssertEqual(result.totalCostUSD, 5)
        XCTAssertEqual(result.totalTokens, 200)
        XCTAssertEqual(result.eventCount, 2)
        XCTAssertEqual(result.totalCostUSD, dashboard.overview.totalCostUSD, accuracy: 0.000_001)
        XCTAssertEqual(result.eventCount, dashboard.overview.eventCount)
    }

    func testUnchangedEventsAgeOutWhenClockAdvances() {
        let now = Date(timeIntervalSince1970: 1_790_296_200)
        let events = [event(at: now.addingTimeInterval(-86_370), cost: 2),
                      event(at: now.addingTimeInterval(-600), cost: 3)]

        let initial = UsageStore.aggregate(events: events, now: now).last24Hours
        let refreshed = UsageStore.aggregate(events: events, now: now.addingTimeInterval(60)).last24Hours

        XCTAssertEqual(initial.totalCostUSD, 5)
        XCTAssertEqual(refreshed.totalCostUSD, 3)
        XCTAssertEqual(refreshed.totalTokens, 100)
        XCTAssertEqual(refreshed.eventCount, 1)
    }

    func testRollingWindowStays24ElapsedHoursAcrossDaylightSavingChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        for components in [DateComponents(year: 2026, month: 3, day: 8, hour: 12),
                           DateComponents(year: 2026, month: 11, day: 1, hour: 12)] {
            let now = try XCTUnwrap(calendar.date(from: components))
            let previousNoon = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
            XCTAssertNotEqual(now.timeIntervalSince(previousNoon), 86_400)
            let events = [event(at: now.addingTimeInterval(-86_400), cost: 2),
                          event(at: now.addingTimeInterval(-86_401), cost: 100)]

            let summary = UsageStore.aggregate(events: events, now: now).last24Hours

            XCTAssertEqual(summary.totalCostUSD, 2)
            XCTAssertEqual(summary.inputTokens, 40)
            XCTAssertEqual(summary.outputTokens, 30)
            XCTAssertEqual(summary.cacheCreationTokens, 20)
            XCTAssertEqual(summary.cacheReadTokens, 10)
            XCTAssertEqual(summary.byModel["gpt-6-sol"]?.eventCount, 1)
        }
    }

    private func event(at timestamp: Date, cost: Double) -> UsageEvent {
        UsageEvent(timestamp: timestamp, model: "gpt-6-sol", inputTokens: 40, outputTokens: 30,
                   cacheCreationTokens: 20, cacheCreation1hTokens: 0, cacheReadTokens: 10,
                   speed: nil, costUSD: cost, sourceApp: "codex", project: "synthetic",
                   sessionID: "rolling-window-test")
    }
}
