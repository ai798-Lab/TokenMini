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


    func testUpgradeReparsesUnchangedRolloutsAndKeepsHistoryAcrossCopiesAndModelSwitches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let active = root.appendingPathComponent("rollout-upgrade.jsonl")
        let oldLocation = root.appendingPathComponent("gone/rollout-upgrade.jsonl")
        let removed = root.appendingPathComponent("rollout-removed.jsonl")
        let ledger = root.appendingPathComponent("usage.plist")
        let time = "2026-10-28T04:00:00Z"
        let when = try XCTUnwrap(ISO8601DateFormatter().date(from: time))
        let settings = #"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-6.2-sol","cwd":"/tmp/upgrade","service_tier":"priority"}}}"#
        let turn = #"{"type":"turn_context","payload":{"model":"gpt-6.1-sol"}}"#
        let change = #"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-6.2-astra"}}}"#
        func usage(total: Int) -> String {
            #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":10},"total_token_usage":{"input_tokens":\#(total),"output_tokens":10}}}}"#
        }
        // Deliberately share a timestamp and delta across real model switches.
        let lines = [settings, usage(total: 100), turn, usage(total: 200), change, usage(total: 300)]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: active)
        let metadata = try active.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        func oldEvent(model: String) -> [String: Any] {
            ["timestamp": when, "model": model, "inputTokens": 100, "cacheReadTokens": 0,
             "outputTokens": 10, "cacheWriteTokens": 0, "identity": "\(time)|\(model)|100|0|0|10"]
        }
        func oldFile(session: String, models: [String]) throws -> [String: Any] {
            ["size": try XCTUnwrap(metadata.fileSize), "mtime": try XCTUnwrap(metadata.contentModificationDate),
             "project": "unknown", "session": session, "events": models.map(oldEvent)]
        }
        let previous = try oldFile(session: "rollout-upgrade", models: ["unknown", "gpt-6.1-sol", "gpt-6.1-sol"])
        let deleted = try oldFile(session: "rollout-removed", models: ["unknown"])
        let bytes = try PropertyListSerialization.data(fromPropertyList: [
            active.path: previous, oldLocation.path: previous, removed.path: deleted
        ], format: .binary, options: 0)
        try bytes.write(to: ledger)
        func scan() -> [UsageEvent] {
            CodexScanner(baseDirectories: [root], ledgerURL: ledger).scanAll(now: auditDate)
        }
        let after = scan()
        let migrated = after.filter { $0.sessionID == "rollout-upgrade" }
        XCTAssertEqual(migrated.count, 3)
        XCTAssertEqual(Set(migrated.map(\.model)), ["gpt-6.1-sol", "gpt-6.2-sol", "gpt-6.2-astra"])
        XCTAssertEqual(migrated.first { $0.model == "gpt-6.2-sol" }?.speed, "fast")
        XCTAssertTrue(migrated.allSatisfy { $0.project == "upgrade" })
        XCTAssertEqual(after.filter { $0.sessionID == "rollout-removed" }.map(\.model), ["unknown"])

        let next = #"{"timestamp":"2026-10-28T04:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":5,"output_tokens":1}}}}"#
        let handle = try FileHandle(forWritingTo: active)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((next + "\n").utf8))
        try handle.close()
        let appended = scan()
        XCTAssertEqual(appended.count, 5)
        try FileManager.default.removeItem(at: active)
        XCTAssertEqual(scan().count, 5, "Restarting after source removal must retain migrated and ledger-only usage")
    }

}
