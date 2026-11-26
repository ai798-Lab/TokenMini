import XCTest
import SQLite3
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

    func testGeminiJSONLMessageUpdatesAndToolTokens() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let dir = home.appendingPathComponent(".gemini/tmp/project/chats")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = ISO8601DateFormatter().string(from: Date())
        let jsonl = """
        {"type":"session_metadata","sessionId":"gem-jsonl-1"}
        {"type":"user","id":"u1","timestamp":"\(now)","content":"hi"}
        {"type":"gemini","id":"m1","timestamp":"\(now)","model":"gemini-3-pro-preview","content":"thinking"}
        {"type":"message_update","id":"m1","tokens":{"input":100,"cached":30,"output":10,"thought":5,"tool":2}}
        {"type":"message_update","id":"m1","tokens":{"input":100,"cached":30,"output":25,"thought":15,"tool":8}}
        {"type":"gemini","id":"m2","timestamp":"\(now)","model":"gemini-3-flash","tokens":{"input":50,"cacheRead":20,"output":10,"reasoningTokens":4}}
        """
        try jsonl.write(to: dir.appendingPathComponent("session-2026-11-20.jsonl"), atomically: true, encoding: .utf8)
        // Duplicate legacy JSON with same sessionId + m2 id must not double count.
        let dupJSON = "{\"sessionId\":\"gem-jsonl-1\",\"messages\":[{\"type\":\"gemini\",\"id\":\"m2\",\"timestamp\":\"\(now)\",\"model\":\"gemini-3-flash\",\"tokens\":{\"input\":50,\"cached\":20,\"output\":10,\"thoughts\":4}}]}"
        try dupJSON.write(to: dir.appendingPathComponent("session-2026-11-20.json"), atomically: true, encoding: .utf8)

        let rows = AdditionalUsageScanner(home: home).scanAll().events.filter { $0.sourceApp == "gemini" }
        XCTAssertEqual(rows.count, 2)
        let m1 = try XCTUnwrap(rows.first { $0.model == "gemini-3-pro-preview" })
        // uncached input = (100 - 30) + tool(8) = 78; output = 25 + thought(15) = 40; cacheRead = 30
        XCTAssertEqual(m1.inputTokens, 78)
        XCTAssertEqual(m1.outputTokens, 40)
        XCTAssertEqual(m1.cacheReadTokens, 30)
        let m2 = try XCTUnwrap(rows.first { $0.model == "gemini-3-flash" })
        XCTAssertEqual(m2.inputTokens, 30)
        XCTAssertEqual(m2.outputTokens, 14)
        XCTAssertEqual(m2.cacheReadTokens, 20)
    }

    func testAntigravityTranscriptProjectCheckpointAndRefresh() throws {
        XCTAssertTrue(ToolKind.antigravity.localScanner)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let agRoot = home.appendingPathComponent(".gemini/antigravity")
        let conv1Log = agRoot.appendingPathComponent("brain/conv-1/.system_generated/logs/transcript.jsonl")
        let conv2Log = agRoot.appendingPathComponent("brain/conv-2/.system_generated/logs/transcript.jsonl")
        try FileManager.default.createDirectory(at: conv1Log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: conv2Log.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Create conversation_summaries.db with a percent-encoded UTF-8 workspace URI for conv-1.
        let dbPath = agRoot.appendingPathComponent("conversation_summaries.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbPath, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let createSQL = "CREATE TABLE conversation_summaries (conversation_id TEXT PRIMARY KEY, workspace_uris TEXT NOT NULL);"
        XCTAssertEqual(sqlite3_exec(db, createSQL, nil, nil, nil), SQLITE_OK)
        let insertSQL = "INSERT INTO conversation_summaries (conversation_id, workspace_uris) VALUES ('conv-1', '[\"file:///Users/test/%E7%9C%9F%E7%88%B1BB%E6%9C%BA\"]');"
        XCTAssertEqual(sqlite3_exec(db, insertSQL, nil, nil, nil), SQLITE_OK)

        let now = ISO8601DateFormatter().string(from: Date())
        let log1 = """
        {"step_index":0,"type":"USER_INPUT","created_at":"\(now)","content":"hello"}
        {"step_index":1,"type":"PLANNER_RESPONSE","status":"RUNNING","created_at":"\(now)","model":"gemini-4-neon-high","input_tokens":1000,"cache_read_tokens":500,"output_tokens":50}
        {"step_index":1,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"\(now)","model":"gemini-4-neon-high","input_tokens":1000,"cache_read_tokens":500,"output_tokens":200}
        {"step_index":2,"type":"CHECKPOINT","status":"DONE","created_at":"\(now)","input_tokens":50000,"cache_read_tokens":0,"output_tokens":800}
        """ + "\n"
        try log1.write(to: conv1Log, atomically: true, encoding: .utf8)

        let log2 = """
        {"step_index":1,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"\(now)","model":"gemini-4-hydrogen-tiered-high","input_tokens":2000,"cache_read_tokens":4000,"output_tokens":300}
        """ + "\n"
        try log2.write(to: conv2Log, atomically: true, encoding: .utf8)

        let scanner = AdditionalUsageScanner(home: home)
        let first = scanner.scanAll()
        let agEvents = first.events.filter { $0.sourceApp == "antigravity" }
        XCTAssertEqual(agEvents.count, 3)
        let agStatus = try XCTUnwrap(first.statuses.first { $0.tool == .antigravity })
        XCTAssertEqual(agStatus.count, 3)

        let conv1Events = agEvents.filter { $0.sessionID == "antigravity:conv-1" }
        XCTAssertEqual(conv1Events.count, 2)
        XCTAssertTrue(conv1Events.allSatisfy { $0.project == "真爱BB机" })
        // step_index 1 updated in place (200 output, not 50 + 200)
        XCTAssertEqual(conv1Events.first?.inputTokens, 1000)
        XCTAssertEqual(conv1Events.first?.cacheReadTokens, 500)
        XCTAssertEqual(conv1Events.first?.outputTokens, 200)
        // CHECKPOINT without a model field keeps "unknown" so tokens are counted without guessing a paid tier.
        XCTAssertEqual(conv1Events.last?.model, "unknown")
        XCTAssertEqual(conv1Events.last?.inputTokens, 50000)
        XCTAssertEqual(conv1Events.last?.outputTokens, 800)

        let conv2Event = try XCTUnwrap(agEvents.first { $0.sessionID == "antigravity:conv-2" })
        XCTAssertEqual(conv2Event.project, "Antigravity")
        XCTAssertEqual(conv2Event.cacheReadTokens, 4000)

        // Append another step and confirm incremental cache invalidates cleanly.
        let extra = "{\"step_index\":3,\"type\":\"PLANNER_RESPONSE\",\"status\":\"DONE\",\"created_at\":\"\(now)\",\"model\":\"gemini-4-neon-high\",\"input_tokens\":300,\"cache_read_tokens\":100,\"output_tokens\":40}\n"
        try (log1 + extra).write(to: conv1Log, atomically: true, encoding: .utf8)
        XCTAssertEqual(scanner.scanAll().events.filter { $0.sourceApp == "antigravity" }.count, 4)
    }

    func testUnpricedUsageSlicesSortDeterministicallyByTokens() {
        let now = Date()
        let ts = now.addingTimeInterval(-10)
        let small = PricedEvent.from(UsageEvent(
            timestamp: ts, model: "unpriced-small-model",
            inputTokens: 100, outputTokens: 10, cacheCreationTokens: 0, cacheCreation1hTokens: 0,
            cacheReadTokens: 0, speed: nil, costUSD: nil, sourceApp: "antigravity",
            project: "SmallProj", sessionID: "antigravity:s1"))
        let big = PricedEvent.from(UsageEvent(
            timestamp: ts, model: "unpriced-big-model",
            inputTokens: 100_000, outputTokens: 1_000, cacheCreationTokens: 0, cacheCreation1hTokens: 0,
            cacheReadTokens: 200_000, speed: nil, costUSD: nil, sourceApp: "antigravity",
            project: "BigProj", sessionID: "antigravity:s2"))
        let dash = UsageAggregator.run([small, big], filter: UsageFilter(time: .today), now: now, calendar: .current)
        XCTAssertEqual(dash.byModel.first?.key, "unpriced-big-model")
        XCTAssertEqual(dash.byProject.first?.key, "BigProj")
        XCTAssertEqual(dash.topSessions.first?.session, "antigravity:s2")

        // Popover summary `topModels` must also break $0 ties by totalTokens so high-volume unpriced models are not truncated.
        var summary = UsagePeriodSummary()
        summary.byModel["paid"] = ModelUsage(costUSD: 1.0, inputTokens: 100)
        summary.byModel["unpriced-small"] = ModelUsage(costUSD: 0, inputTokens: 10_000_000)
        summary.byModel["unpriced-medium"] = ModelUsage(costUSD: 0, inputTokens: 200_000_000)
        summary.byModel["codex-auto-review"] = ModelUsage(costUSD: 0, inputTokens: 230_000_000)
        XCTAssertEqual(summary.topModels.map(\.key), [
            "paid", "codex-auto-review", "unpriced-medium", "unpriced-small"
        ])
    }

    func testGemini4AndLegacyGooglePricingAndStrictAliases() throws {
        for (id, input, output, read) in [
            ("gemini-4-neon", 3.0, 15.0, 0.15),
            ("gemini-4-neon-high", 3.0, 15.0, 0.15),
            ("gemini-4-hydrogen", 1.5, 7.5, 0.075),
            ("gemini-4-hydrogen-tiered-high", 1.5, 7.5, 0.075),
            ("gemini-4-carbon-high", 4.0, 20.0, 0.2),
            ("gemini-4-argon-medium", 4.0, 20.0, 0.2),
            ("gemini-3.8-flash-high", 0.75, 3.75, 0.075),
            ("gemini-3.5-flash", 1.5, 9.0, 0.15),
            ("gemini-3.5-flash-lite", 0.3, 2.5, 0.03),
            ("gemini-3.1-pro-preview", 2.0, 12.0, 0.2),
            ("gemini-3.1-pro-high", 2.0, 12.0, 0.2),
            ("gemini-3.1-flash-lite", 0.25, 1.5, 0.025),
            ("gemini-2.5-flash-lite", 0.1, 0.4, 0.01)
        ] {
            let p = try XCTUnwrap(PricingTable.pricing(for: id), id)
            XCTAssertEqual(p.inputPerMTok, input, id)
            XCTAssertEqual(p.outputPerMTok, output, id)
            XCTAssertEqual(p.cacheReadPerMTok, read, id)
            XCTAssertEqual(p.cacheWritePerMTok, 0, id)
        }
        // Strict alias policy: unknown suffixes must never fall back to base prices.
        XCTAssertNil(PricingTable.pricing(for: "gemini-4-neon-invented"))
        XCTAssertNil(PricingTable.pricing(for: "gemini-4-hydrogen-unknown"))
    }

    func testGPT62AndClaudeFable52PricingAndThreadSettingsFallback() throws {
        let sol = try XCTUnwrap(PricingTable.pricing(for: "gpt-6.2-sol"))
        XCTAssertEqual(sol.inputPerMTok, 2)
        XCTAssertEqual(sol.outputPerMTok, 10)
        XCTAssertEqual(sol.cacheWritePerMTok, 2.5)
        XCTAssertEqual(sol.cacheReadPerMTok, 0.1)
        XCTAssertEqual(sol.fullRequestThreshold, 272_000)
        XCTAssertEqual(PricingTable.fastMultiplier(for: "gpt-6.2-sol"), 2)

        let astra = try XCTUnwrap(PricingTable.pricing(for: "gpt-6.2-astra"))
        XCTAssertEqual(astra.inputPerMTok, 8)
        XCTAssertEqual(astra.outputPerMTok, 40)
        XCTAssertEqual(astra.cacheWritePerMTok, 10)
        XCTAssertEqual(astra.cacheReadPerMTok, 0.4)
        XCTAssertEqual(astra.fullRequestThreshold, 272_000)
        XCTAssertEqual(PricingTable.fastMultiplier(for: "gpt-6.2-astra"), 2)

        // >272K long-context full-request scaling for GPT-6.2 Sol (2x input/cache, 1.5x output)
        let over = sol.breakdown(input: 2_001, output: 1_000, cacheWrite: 0, cacheWrite1h: 0, cacheRead: 270_000)
        XCTAssertEqual(over.output, 10 * 0.0015, accuracy: 0.000001)
        XCTAssertEqual(over.cacheRead, 0.1 * 0.54, accuracy: 0.000001)

        let fable = try XCTUnwrap(PricingTable.pricing(for: "claude-fable-5.2"))
        XCTAssertEqual(fable.inputPerMTok, 8)
        XCTAssertEqual(fable.outputPerMTok, 40)
        XCTAssertEqual(fable.cacheWritePerMTok, 10)
        XCTAssertEqual(fable.cacheWrite1hPerMTok, 16)
        XCTAssertEqual(fable.cacheReadPerMTok, 0.2)
        XCTAssertEqual(PricingTable.fastMultiplier(for: "claude-fable-5-2"), 2)
        XCTAssertNil(PricingTable.pricing(for: "gpt-6.2-invented"))

        // CodexScanner falls back to thread_settings_applied when no turn_context precedes token_count.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = ISO8601DateFormatter().string(from: Date())
        let settings = "{\"timestamp\":\"\(date)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"thread_settings_applied\",\"thread_settings\":{\"model\":\"gpt-6.2-sol\",\"cwd\":\"/tmp/demo-proj\"}}}\n"
        let usage = "{\"timestamp\":\"\(date)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":1000,\"cached_input_tokens\":400,\"cache_write_input_tokens\":0,\"output_tokens\":100},\"last_token_usage\":{\"input_tokens\":1000,\"cached_input_tokens\":400,\"cache_write_input_tokens\":0,\"output_tokens\":100}}}}\n"
        try (settings + usage).write(to: root.appendingPathComponent("rollout-62-test.jsonl"), atomically: true, encoding: .utf8)
        let events = CodexScanner(baseDirectories: [root]).scanAll()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.model, "gpt-6.2-sol")
        XCTAssertEqual(events.first?.project, "demo-proj")
        XCTAssertEqual(events.first?.inputTokens, 600)
        XCTAssertEqual(events.first?.cacheReadTokens, 400)
        XCTAssertEqual(events.first?.outputTokens, 100)
        XCTAssertTrue(PricedEvent.from(events[0]).isPriced)
    }

    func testLiveTodayCodex62WhenRequested() throws {
        guard ProcessInfo.processInfo.environment["MACPULSE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Explicit local acceptance only")
        }
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month, .day], from: now)
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", comps.year!, comps.month!, comps.day!))
        guard FileManager.default.fileExists(atPath: dir.path) else { throw XCTSkip("No today Codex dir") }
        let events = CodexScanner(baseDirectories: [dir]).scanAll(now: now)
        let agg = UsageStore.aggregate(events: events, now: now)
        print("LIVE_TODAY_CODEX events=\(agg.today.eventCount) tokens=\(agg.today.totalTokens) costUSD=\(String(format: "%.2f", agg.today.totalCostUSD))")
        for (model, m) in agg.today.topModels {
            let priced = PricingTable.pricing(for: model) != nil
            print("  MODEL \(model): events=\(m.eventCount) tokens=\(m.totalTokens) in=\(m.inputTokens) cr=\(m.cacheReadTokens) cw=\(m.cacheCreationTokens) out=\(m.outputTokens) costUSD=\(String(format: "%.2f", m.costUSD)) priced=\(priced)")
        }
        if let sol = agg.today.byModel["gpt-6.2-sol"] {
            XCTAssertGreaterThan(sol.totalTokens, 0)
            XCTAssertGreaterThan(sol.costUSD, 0)
        }
    }
}
