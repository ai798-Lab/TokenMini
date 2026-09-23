import XCTest
@testable import MacPulse

final class TrendAxisLayoutTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return c
    }
    private func points(hour: Int = 13, count: Int = 25, days: Bool = false) -> [TrendPoint] {
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: hour))!
        return (0..<count).map { i in
            TrendPoint(id: i, label: "unique-\(i)", date: cal.date(byAdding: days ? .day : .hour, value: i, to: start)!)
        }
    }
    func testCrossDayKeepsUniqueBucketsAndUsesShortTimeLabels() {
        let layout = TrendAxisLayout(points: points(), hourly: true, calendar: cal)
        XCTAssertEqual(layout.points.count, 25)
        XCTAssertEqual(layout.shortLabel(for: "unique-0"), "13:00")
        XCTAssertEqual(layout.shortLabel(for: "unique-24"), "13:00")
        XCTAssertEqual(layout.dateMarkers(plotWidth: 900).map(\.text), ["09/22", "09/23"])
        XCTAssertEqual(Set(layout.ticks(plotWidth: 900)).count, layout.ticks(plotWidth: 900).count)
    }
    func testHourlyTicksRespectNarrowAndWideSpacing() {
        for width in [240.0, 420, 640, 1000] {
            let layout = TrendAxisLayout(points: points(), hourly: true, calendar: cal)
            let indices = layout.ticks(plotWidth: width).compactMap { key in layout.points.firstIndex { $0.label == key } }
            XCTAssertLessThanOrEqual(indices.count, max(1, Int(width / 72)))
            for (a,b) in zip(indices, indices.dropFirst()) {
                XCTAssertGreaterThanOrEqual(Double(b-a) * width / 25, 72)
            }
        }
    }
    func testMidnightNearLeftEdgeDoesNotCrowdDateRow() {
        let layout = TrendAxisLayout(points: points(hour: 23), hourly: true, calendar: cal)
        XCTAssertEqual(layout.dateMarkers(plotWidth: 420).map(\.text), ["09/23"])
    }
    func testDailyTicksRemainSparseWithoutDroppingDailyData() {
        let layout = TrendAxisLayout(points: points(count: 31, days: true), hourly: false, calendar: cal)
        XCTAssertEqual(layout.points.count, 31)
        XCTAssertLessThanOrEqual(layout.ticks(plotWidth: 420).count, 5)
        XCTAssertEqual(layout.shortLabel(for: "unique-0"), "09/22")
        XCTAssertTrue(layout.dateMarkers(plotWidth: 420).isEmpty)
    }
    func testEmptyAndSingleBucket() {
        XCTAssertEqual(TrendAxisLayout(points: [], hourly: true).ticks(plotWidth: 0), [])
        let layout = TrendAxisLayout(points: points(count: 1), hourly: true, calendar: cal)
        XCTAssertEqual(layout.ticks(plotWidth: 0), ["unique-0"])
    }
}
