import XCTest
@testable import MacPulse

final class CompressedHistoryTests: XCTestCase {
    private let auditDate = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z")!
    private let plain = #"{"type":"session_meta","payload":{"id":"fixture-session","cwd":"/example/project"}}"# + "\n"
        + #"{"type":"turn_context","payload":{"model":"gpt-6.1-terra"}}"# + "\n"
        + #"{"timestamp":"2026-10-28T04:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20},"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20}}}}"# + "\n"
    // Official zstd 1.5.7 CLI compressed a synthetic rollout: 100 input (40 cached), 20 output.
    private let compressed = Data(base64Encoded: "KLUv/QRYnQYA4k0qIGBJqwMG+xiUH7bXZhY/CkKs0CB4xEBwrRVs50WQS+AEhRijst36J6bRsP3kIR1MoFb9ZBb6Bx1jZB9M/VZ5o28Jlvy8GWwqMTZoyFupGR/w+UCmZuohBQIMlAVCGGlc79b245XssnCjAgCB2iHXK3y01Qw3ayqxBXYhxrfigrY4AytuLcOG6w8E9XPEC2wmSVx/JG/0xzYlYd3Pt3kl1pL3+F3PLqHfBA4AhQUEAIZsckZPWXGcIz/x9BkIeGLNTMqI4ZFfuRck7Qo6g8rUHuA2828=")!

    func testCompressedHistoricalUsageIsIncluded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try compressed.write(to: root.appendingPathComponent("rollout-fixture.jsonl.zst"))
        let events = CodexScanner(baseDirectories: [root]).scanAll(now: auditDate)
        XCTAssertEqual(events.count, 1, "压缩会话不能使历史用量消失")
        XCTAssertEqual(events.first?.inputTokens, 60)
        XCTAssertEqual(events.first?.cacheReadTokens, 40)
        XCTAssertEqual(events.first?.outputTokens, 20)
    }

    func testCompressionMigrationAndMirroredFilesKeepSameHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("rollout-fixture.jsonl")
        let archive = root.appendingPathComponent("rollout-fixture.jsonl.zst")
        try Data(plain.utf8).write(to: original)
        let scanner = CodexScanner(baseDirectories: [root])
        let before = scanner.scanAll(now: auditDate)
        XCTAssertEqual(before.count, 1)
        try compressed.write(to: archive)
        XCTAssertEqual(scanner.scanAll(now: auditDate).count, 1, "Migration overlap must not double count")
        try FileManager.default.removeItem(at: original)
        let after = scanner.scanAll(now: auditDate)
        XCTAssertEqual(after.count, 1, "Replacing the source by its compressed copy must retain history")
        XCTAssertEqual(after.first?.sessionID, before.first?.sessionID)
        XCTAssertEqual(after.first.map { PricedEvent.from($0).totalTokens }, 120)
        XCTAssertEqual(after.first.map { PricedEvent.from($0).cost.total }, before.first.map { PricedEvent.from($0).cost.total })
    }

    func testCorruptArchiveReportsFailureAndRetainsPreviouslyVerifiedUsage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("rollout-fixture.jsonl.zst")
        try compressed.write(to: archive)
        let scanner = CodexScanner(baseDirectories: [root])
        XCTAssertEqual(scanner.scanAll(now: auditDate).count, 1)
        try compressed.dropLast(8).write(to: archive)
        XCTAssertEqual(scanner.scanAll(now: auditDate).count, 1)
        XCTAssertEqual(scanner.readFailures, 1)
        let fresh = CodexScanner(baseDirectories: [root])
        XCTAssertTrue(fresh.scanAll(now: auditDate).isEmpty, "Never publish a truncated archive as complete")
        XCTAssertEqual(fresh.readFailures, 1)
    }

    func testMeteringSurvivesSourceRemovalAndAppRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("rollout-fixture.jsonl")
        let ledger = root.appendingPathComponent("ledger/history.plist")
        try Data(plain.utf8).write(to: source)
        XCTAssertEqual(CodexScanner(baseDirectories: [root], ledgerURL: ledger).scanAll(now: auditDate).count, 1)
        try FileManager.default.removeItem(at: source)
        let restarted = CodexScanner(baseDirectories: [root], ledgerURL: ledger)
        XCTAssertEqual(restarted.scanAll(now: auditDate).count, 1)
        XCTAssertFalse(restarted.historyPersistenceFailed)
        // Reappearing compressed copy still represents the same request.
        try compressed.write(to: root.appendingPathComponent("rollout-fixture.jsonl.zst"))
        XCTAssertEqual(restarted.scanAll(now: auditDate).count, 1)
        let text = String(decoding: try Data(contentsOf: ledger), as: UTF8.self)
        XCTAssertFalse(text.contains("session_meta"), "Ledger stores metering, never the conversation")
    }

}
