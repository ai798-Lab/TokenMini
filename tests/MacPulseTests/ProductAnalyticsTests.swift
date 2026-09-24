import XCTest
@testable import MacPulse

final class ProductAnalyticsTests: XCTestCase {
    func testOptInPersistsAndRevocationErasesUnsentIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("outbox.json")
        var queue = AnalyticsOutbox(file: file, cohort: "upgrade")
        queue.record(.appStart, at: Date(timeIntervalSince1970: 100))
        XCTAssertTrue(queue.events.isEmpty)
        queue.setEnabled(true)
        let oldID = queue.profileID
        queue.record(.appStart, at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(queue.events.count, 2) // consent observation + launch
        let originalEvent = queue.events.last!
        queue = AnalyticsOutbox(file: file, cohort: "new")
        XCTAssertTrue(queue.enabled)
        XCTAssertEqual(queue.events.last?.id, originalEvent.id)
        XCTAssertEqual(queue.events.last?.occurredAt, originalEvent.occurredAt)
        XCTAssertEqual(queue.cohort, "upgrade")
        queue.setEnabled(false)
        XCTAssertTrue(queue.events.isEmpty)
        XCTAssertNil(queue.profileID)
        queue = AnalyticsOutbox(file: file, cohort: "new")
        XCTAssertFalse(queue.enabled)
        queue.setEnabled(true)
        XCTAssertNotEqual(queue.profileID, oldID)
    }

    func testAckOnlyRemovesConfirmedEventsAndQueueIsBounded() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = AnalyticsOutbox(file: file, cohort: "unknown", limit: 3)
        queue.setEnabled(true)
        let first = queue.events[0].id
        for _ in 0..<5 { queue.record(.appStart) }
        XCTAssertEqual(queue.events.count, 3)
        // Preserve the cohort origin even when the queue overflows.
        XCTAssertEqual(queue.events[0].id, first)
        queue.acknowledge("not-the-request")
        XCTAssertEqual(queue.events.count, 3)
        queue.acknowledge(first)
        XCTAssertEqual(queue.events.count, 2)
    }

    func testClockExcludesHiddenIdleSleepAndDoesNotMultiplyWindows() {
        var clock = AnalyticsClock()
        XCTAssertEqual(clock.sample(uptime: 0, running: true, interacting: true), .zero)
        XCTAssertEqual(clock.sample(uptime: 5, running: true, interacting: true), .init(runtime: 5, interaction: 5))
        XCTAssertEqual(clock.sample(uptime: 10, running: true, interacting: false), .init(runtime: 5, interaction: 0))
        XCTAssertEqual(clock.sample(uptime: 15, running: false, interacting: false), .zero)
        XCTAssertEqual(clock.sample(uptime: 3600, running: true, interacting: true), .zero)
        XCTAssertEqual(clock.sample(uptime: 3605, running: true, interacting: true), .init(runtime: 5, interaction: 5))
    }

    func testWirePayloadHasOriginalTimestampAndNoPersonalData() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = AnalyticsOutbox(file: file, cohort: "upgrade")
        queue.setEnabled(true)
        queue.record(.engagement, at: Date(timeIntervalSince1970: 1_700_000_000), runtime: 30, interaction: 10)
        let event = queue.events.last!
        let body = try JSONSerialization.jsonObject(with: event.openPanelBody()) as! [String: Any]
        let payload = body["payload"] as! [String: Any]
        let props = payload["properties"] as! [String: Any]
        XCTAssertEqual(props["__timestamp"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(props["event_id"] as? String, event.id)
        XCTAssertEqual(props["interaction_seconds"] as? Double, 10)
        XCTAssertEqual(Set(props.keys), ["product", "platform", "version", "cohort", "event_id", "__timestamp", "runtime_seconds", "interaction_seconds"])
    }
}
