import XCTest
@testable import MacPulse

final class MultiToolTests: XCTestCase {
    func testCurrentOfficialPricesAndUnknownModels() {
        XCTAssertEqual(PricingTable.pricing(for: "gpt-6-astra")?.inputPerMTok, 10)
        XCTAssertEqual(PricingTable.pricing(for: "gpt-5.6-sol")?.inputPerMTok, 4)
        XCTAssertEqual(PricingTable.pricing(for: "gpt-5.6-luna")?.inputPerMTok, 0.2)
        XCTAssertEqual(PricingTable.pricing(for: "claude-fable-5-1")?.cacheReadPerMTok, 0.25)
        XCTAssertEqual(PricingTable.pricing(for: "DeepSeek-V4-Pro 正式版")?.inputPerMTok, 1.32)
        XCTAssertNil(PricingTable.pricing(for: "codex-auto-review"))
        XCTAssertNil(PricingTable.pricing(for: "gpt-6-astra-invented"))
    }
    func testToolIdentityDoesNotFallBackToClaude() {
        XCTAssertNotNil(ToolKind(sourceApp: "kimi"))
        XCTAssertNotNil(ToolKind(sourceApp: "cursor"))
        XCTAssertNotNil(ToolKind(sourceApp: "trae"))
    }
}

extension MultiToolTests {
    func testKimiModernAndMigrationCopiesAndRefresh() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let a = home.appendingPathComponent(".kimi-code/sessions/project/session/agents/main/wire.jsonl")
        let b = home.appendingPathComponent(".kimi/sessions/project/session/wire.jsonl")
        try FileManager.default.createDirectory(at: a.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let row = "{\"type\":\"usage.record\",\"time\":\(ts),\"model\":\"kimi-code/k3\",\"usageScope\":\"turn\",\"usage\":{\"inputOther\":100,\"output\":20,\"inputCacheRead\":80,\"inputCacheCreation\":5}}\n"
        try row.write(to: a, atomically: true, encoding: .utf8)
        try (row + row.replacingOccurrences(of: "turn", with: "session")).write(to: b, atomically: true, encoding: .utf8)
        let scanner = AdditionalUsageScanner(home: home)
        let first = scanner.scanAll().events
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.inputTokens, 100)
        XCTAssertEqual(first.first?.cacheReadTokens, 80)
        XCTAssertEqual(first.first?.model, "kimi-code/k3")
        XCTAssertEqual(scanner.scanAll().events.count, 1)
        try (row + row.replacingOccurrences(of: "\(ts)", with: "\(ts + 1)")).write(to: a, atomically: true, encoding: .utf8)
        XCTAssertEqual(scanner.scanAll().events.count, 2)
    }
    func testCursorCSVAndGenericUnknownModel() throws {
        let csv = "Date,Model,Input (w/ Cache Write),Output Tokens,Cache Read,Cost\r\n2026-09-22T00:00:00Z,unknown-future-model,100,20,50,Included\r\n"
        let rows = try UsageImport.parse(Data(csv.utf8), format: "csv", tool: .cursor)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].input, 100)
        XCTAssertEqual(rows[0].cacheRead, 50)
        XCTAssertNil(rows[0].costUSD)
        XCTAssertFalse(PricedEvent.from(rows[0].event).isPriced)
        XCTAssertEqual(try UsageImport.parse(Data(csv.utf8), format: "csv", tool: .cursor).first?.id, rows[0].id)
        XCTAssertThrowsError(try UsageImport.parse(Data("Date,Model\n2026-09-22,x".utf8), format: "csv", tool: .cursor))
    }
    func testGenericImportValidationAndCostEvidence() throws {
        let row = #"{"id":"one","timestamp":"2026-09-22T00:00:00Z","model":"future-model","input":10,"output":5,"cacheRead":0,"cacheWrite":0,"costUSD":0}"#
        let records = try UsageImport.parse(Data(row.utf8), format: "jsonl", tool: .traeWork)
        XCTAssertEqual(records[0].event.sourceApp, "traeWork")
        XCTAssertTrue(PricedEvent.from(records[0].event).isPriced)
        XCTAssertThrowsError(try UsageImport.parse(Data(row.replacingOccurrences(of: "\"input\":10", with: "\"input\":-10").utf8), format: "jsonl", tool: .trae))
    }
}

extension MultiToolTests {
    func testCodexRepeatedSnapshotAndCacheWrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = ISO8601DateFormatter().string(from: Date())
        let context = "{\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-6-astra\",\"service_tier\":\"fast\"}}\n"
        let event = "{\"timestamp\":\"\(date)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":40,\"cache_write_input_tokens\":10,\"output_tokens\":20},\"last_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":40,\"cache_write_input_tokens\":10,\"output_tokens\":20}}}}\n"
        try (context + event + event).write(to: root.appendingPathComponent("rollout-test.jsonl"), atomically: true, encoding: .utf8)
        let events = CodexScanner(baseDirectories: [root]).scanAll()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.inputTokens, 50)
        XCTAssertEqual(events.first?.cacheCreationTokens, 10)
        XCTAssertEqual(events.first?.speed, "fast")
    }
}

extension MultiToolTests {
    func testCommunityCatalogAndExactProviderNames() {
        XCTAssertGreaterThan(PricingTable.communityPrices.count, 2500)
        XCTAssertNotNil(PricingTable.pricing(for: "@cf/aisingapore/gemma-sea-lion-v4-27b-it"))
        XCTAssertNil(PricingTable.pricing(for: "invented/gemma-sea-lion-v4-27b-it"))
        XCTAssertNil(PricingTable.communityPrices["ByteDance/Seed-2.0-code"], "Unsupported context tiers must not silently use a flat price")
    }
    func testCursorCacheWriteIsDifferenceNotDoubleCounted() throws {
        let csv = "Date,Model,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Cost\n2026-09-22T00:00:00Z,test,150,100,80,20,0.42\n"
        let row = try XCTUnwrap(UsageImport.parse(Data(csv.utf8), format: "csv", tool: .cursor).first)
        XCTAssertEqual(row.input, 100)
        XCTAssertEqual(row.cacheWrite, 50)
        XCTAssertEqual(PricedEvent.from(row.event).totalTokens, 250)
        XCTAssertEqual(PricedEvent.from(row.event).cost.total, 0.42, accuracy: 0.0001)
    }
    func testTraeUpstreamNormalizationAndInvalidPages() throws {
        let raw = #"{"data":{"total":2,"user_usage_group_by_sessions":[{"session_id":"one","model_name":"doubao-pro","usage_time":1700000000,"input_token":100,"output_token":10,"cache_read_token":30,"cache_write_token":40},{"session_id":"two","usage_time":1700002000,"extra_info":{"input_token":5,"output_token":6,"cache_read_token":7,"cache_write_token":8}}]}}"#
        let page = try TraeUsageClient.parsePage(Data(raw.utf8))
        XCTAssertEqual(page.total, 2)
        XCTAssertEqual(page.rows[0].input, 30)
        XCTAssertEqual(PricedEvent.from(page.rows[0].event).totalTokens, 110)
        XCTAssertEqual(page.rows[1].cacheRead, 5)
        XCTAssertEqual(page.rows[1].cacheWrite, 0)
        var blankModel = page.rows[1]; blankModel.model = " "
        XCTAssertEqual(blankModel.event.model, "unknown")
        XCTAssertThrowsError(try TraeUsageClient.parsePage(Data(raw.replacingOccurrences(of: "\"total\":2", with: "\"total\":true").utf8)))
        XCTAssertThrowsError(try TraeUsageClient.parsePage(Data("{}".utf8)))
    }
    func testTraeCredentialCompatibilityWithSyntheticUpstreamFixture() throws {
        // Generated with TokenTracker's MIT deriveTraeCnKeyIv; never a real account credential.
        let blob = Data(base64Encoded: "dGMFEAAABwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwdexbaE2Cdwi0P8U01RPhPZ/07UrrMGB8cmVX7N1hpsK8oDqMpgXUi7chZ6aat2Fx35cmi5Ch8hyaTq6oXOjlZmaapoYK/iu9BIgslyp5DTdDleitE+YQcCHFcMw+kw0Co=")!
        XCTAssertEqual(String(data: try TraeUsageClient.decrypt(blob), encoding: .utf8), #"{"token":"synthetic-test-only"}"#)
        var corrupted = blob; corrupted[50] ^= 1
        XCTAssertThrowsError(try TraeUsageClient.decrypt(corrupted))
    }
    func testLiveAdditionalSourcesWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["MACPULSE_LIVE_TEST"] == "1" else { throw XCTSkip("Explicit local acceptance only") }
        let scanner = AdditionalUsageScanner()
        let result = scanner.scanAll()
        for status in result.statuses { print("SOURCE \(status.tool.rawValue): \(status.count), \(status.detail)") }
        XCTAssertTrue(result.events.allSatisfy { PricedEvent.from($0).totalTokens >= 0 })
        XCTAssertEqual(scanner.scanAll().events.count, result.events.count)
    }
}

extension MultiToolTests {
    func testBlankImportIDsDoNotCollapseDistinctRows() throws {
        let csv = "timestamp,model,input,output,id\n2026-09-22T00:00:00Z,test,10,1,\n2026-09-22T00:01:00Z,test,10,1,\n"
        let rows = try UsageImport.parse(Data(csv.utf8), format: "csv", tool: .other)
        XCTAssertEqual(Set(rows.map(\.id)).count, 2)
        XCTAssertNil(UsageRecord.date(true))
    }
    func testGeminiThoughtsAndDistinctMissingMessageIDs() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".gemini/tmp/project/chats/session-test.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let now = Date().timeIntervalSince1970
        let text = "{\"sessionId\":\"gem\",\"messages\":[{\"type\":\"gemini\",\"timestamp\":\(now),\"model\":\"gemini-3.8-flash\",\"tokens\":{\"input\":100,\"cached\":40,\"output\":20,\"thoughts\":10}},{\"type\":\"gemini\",\"timestamp\":\(now-1),\"model\":\"gemini-3.8-flash\",\"tokens\":{\"input\":100,\"cached\":40,\"output\":20,\"thoughts\":10}}]}"
        try text.write(to: file, atomically: true, encoding: .utf8)
        let rows = AdditionalUsageScanner(home: home).scanAll().events
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.inputTokens, 60)
        XCTAssertEqual(rows.first?.outputTokens, 30)
    }
}
