import Foundation
import CryptoKit
import SQLite3

struct ToolSourceStatus: Identifiable, Sendable {
    let tool: ToolKind
    var id: String { tool.rawValue }
    var count: Int = 0
    var detail: String
}

/// Local, read-only adapters. Never reads credentials or sends conversation content anywhere.
/// Cached files hold usage only; messages/prompts are discarded immediately.
// Like the existing scanners, all mutable cache access is confined to UsageStore.scanQueue.
final class AdditionalUsageScanner: @unchecked Sendable {
    struct Result { var events: [UsageEvent]; var statuses: [ToolSourceStatus] }
    private struct Cached {
        var size: Int, modified: Date, project: String? = nil, records: [UsageRecord]
    }
    private static let agInputMarker = Data("input_tokens".utf8)
    private static let agOutputMarker = Data("output_tokens".utf8)
    private static let agCacheReadMarker = Data("cache_read_tokens".utf8)
    private static let agCacheCreateMarker = Data("cache_creation_tokens".utf8)
    private static let kimiUsageMarker = Data("usage.record".utf8)
    private static let kimiStatusMarker = Data("StatusUpdate".utf8)
    private static let hexTable: [UInt8] = Array("0123456789abcdef".utf8)
    private let home: URL
    private let apiScanner = APIUsageScanner()
    private var cache: [String: Cached] = [:]
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    func scanAll() -> Result {
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        var records: [UsageRecord] = []
        var seen = Set<String>(), visited = Set<String>()
        var errors: [ToolKind: Int] = [:]
        do { errors[.deepseekAPI] = try apiScanner.scan(home: home) }
        catch { errors[.deepseekAPI, default: 0] += 1 }
        for (tool, root, fileName) in [
            (ToolKind.kimi, ".kimi-code/sessions", "wire.jsonl"),
            (.kimi, ".kimi/sessions", "wire.jsonl"),
            (.gemini, ".gemini/tmp", "session-")
        ] {
            let rootURL = home.appendingPathComponent(root)
            guard FileManager.default.fileExists(atPath: rootURL.path) else { continue }
            guard let en = FileManager.default.enumerator(at: rootURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles], errorHandler: { _, _ in errors[tool, default: 0] += 1; return true }) else {
                errors[tool, default: 0] += 1; continue
            }
            for case let file as URL in en {
                let ext = file.pathExtension.lowercased()
                guard (tool == .kimi && file.lastPathComponent == fileName)
                    || (tool == .gemini && file.lastPathComponent.hasPrefix(fileName) && (ext == "json" || ext == "jsonl")) else { continue }
                visited.insert(file.path)
                do {
                    let rv = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
                    guard rv.isRegularFile == true else { continue }
                    let size = rv.fileSize ?? 0, modified = rv.contentModificationDate ?? .distantPast
                    // A file last written before retention cannot contain a newer usage event.
                    guard modified >= cutoff else { continue }
                    let rows: [UsageRecord]
                    if let hit = cache[file.path], hit.size == size, hit.modified == modified { rows = hit.records }
                    else {
                        if tool == .kimi {
                            rows = try parseKimi(file: file, cutoff: cutoff)
                        } else if tool == .gemini && ext == "jsonl" {
                            rows = try parseGeminiJSONL(file: file, cutoff: cutoff)
                        } else {
                            let data = try Data(contentsOf: file, options: .alwaysMapped)
                            rows = parseGemini(data, file: file, cutoff: cutoff)
                        }
                        cache[file.path] = Cached(size: size, modified: modified, records: rows)
                    }
                    for row in rows where row.timestamp >= cutoff && seen.insert(row.id).inserted { records.append(row) }
                } catch { errors[tool, default: 0] += 1 }
            }
        }
        for row in scanAntigravity(cutoff: cutoff, visited: &visited, errors: &errors)
            where row.timestamp >= cutoff && seen.insert(row.id).inserted {
            records.append(row)
        }
        cache = cache.filter { visited.contains($0.key) }
        do { records += try scanOpenCode(cutoff: cutoff) } catch { errors[.opencode, default: 0] += 1 }
        do { records += try TraeUsageClient.cached(home: home).filter { $0.timestamp >= cutoff } }
        catch { errors[.traeWork, default: 0] += 1 }
        var statuses: [ToolSourceStatus] = [ToolKind.kimi, .gemini, .opencode, .antigravity].map { tool in
            let count = records.filter { $0.tool == tool }.count
            let detail = errors[tool, default: 0] > 0 ? L10n.text("部分记录读取失败（\(errors[tool]!) 处）") : count > 0 ? L10n.text("本地记录 · 自动更新") : L10n.text("近 90 天未发现可读取用量")
            return ToolSourceStatus(tool: tool, count: count, detail: detail)
        }
        do {
            let imported = try UsageImport.load(home: home)
            records += imported.filter { $0.timestamp >= cutoff }
            for tool in ToolKind.allCases where !tool.localScanner {
                let count = records.filter { $0.tool == tool && $0.timestamp >= cutoff }.count
                if tool == .deepseekAPI {
                    let detail = errors[tool, default: 0] > 0 ? L10n.text("部分 API 用量记录读取失败，已保留历史记录")
                        : count > 0 ? L10n.text("本机 API 用量账本 · 每 60 秒自动更新") : L10n.text("待接入调用日志；官方余额见上方，不能由余额反推 Token")
                    statuses.append(ToolSourceStatus(tool: tool, count: count, detail: detail))
                    continue
                }
                statuses.append(ToolSourceStatus(tool: tool, count: count,
                    detail: tool == .traeWork ? (errors[.traeWork, default: 0] > 0 ? L10n.text("同步缓存读取失败") : count > 0 ? L10n.text("官方用量缓存 / 导入记录 · 在下方更新") : L10n.text("可选：同步 Trae Work CN 官方用量")) : count > 0 ? L10n.text("已导入 · 不自动同步工具账号") : tool == .cursor ? L10n.text("待导入 Cursor 用量 CSV") : L10n.text("待接入 · 支持通用用量文件导入")))
            }
        } catch {
            statuses.append(ToolSourceStatus(tool: .other, detail: L10n.text("导入记录读取失败：\(error.localizedDescription)")))
        }
        return Result(events: records.map(\.event), statuses: statuses)
    }

    private func parseKimi(file: URL, cutoff: Date) throws -> [UsageRecord] {
        var rows: [UsageRecord] = []
        let parts = file.pathComponents
        let session: String = parts.firstIndex(of: "agents").map { parts[$0 - 1] }
            ?? file.deletingLastPathComponent().lastPathComponent
        // Only parse metering records, never context.append_loop_event / turn.prompt bodies.
        try UsageLogReader.forEachLine(at: file) { line in
            guard line.count <= 1_048_576,
                  line.range(of: Self.kimiUsageMarker) != nil || line.range(of: Self.kimiStatusMarker) != nil else { return }
            autoreleasepool {
                guard let d = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
                let message = d["message"] as? [String: Any] ?? d
                let modern = message["type"] as? String == "usage.record"
                if modern && message["usageScope"] as? String != "turn" { return }
                let payload = message["payload"] as? [String: Any] ?? [:]
                guard modern || message["type"] as? String == "StatusUpdate",
                      let u = (modern ? message["usage"] : payload["token_usage"]) as? [String: Any],
                      let timestamp = UsageRecord.date(modern ? message["time"] : d["timestamp"]), timestamp >= cutoff else { return }
                let model = (modern ? message["model"] : payload["model"]) as? String ?? "unknown"
                let i = Self.token(u, modern ? "inputOther" : "input_other")
                let o = Self.token(u, "output")
                let r = Self.token(u, modern ? "inputCacheRead" : "input_cache_read")
                let w = Self.token(u, modern ? "inputCacheCreation" : "input_cache_creation")
                guard i + o + r + w > 0 else { return }
                // Adapted from ccusage kimi_entry_key (MIT): dedupe by session/message/time/usage,
                // independent of JSON whitespace or extra fields. Keep raw model for display.
                let messageID = payload["message_id"] as? String ?? ""
                let key = "\(session)|\(messageID)|\(timestamp.timeIntervalSince1970)|\(model)|\(i)|\(o)|\(w)|\(r)"
                rows.append(UsageRecord(id: "kimi:" + Self.digest(Data(key.utf8)), timestamp: timestamp, tool: .kimi,
                    model: model, input: i, output: o, cacheWrite: w, cacheRead: r, project: "Kimi Code", session: "kimi:" + session))
            }
        }
        return rows
    }

    private func geminiTokenCounts(_ t: [String: Any]) -> (input: Int, output: Int, cacheRead: Int) {
        let rawInput = Self.token(t, "input")
        let cached = min(rawInput, max(Self.token(t, "cached"), Self.token(t, "cacheRead")))
        // In Gemini CLI, total = input + output + thoughts + tool, while cached is a subset of input.
        let toolTokens = Self.token(t, "tool")
        let thoughts = max(Self.token(t, "thoughts"), max(Self.token(t, "thought"), Self.token(t, "reasoningTokens")))
        return (input: (rawInput - cached) + toolTokens, output: Self.token(t, "output") + thoughts, cacheRead: cached)
    }

    private func parseGemini(_ data: Data, file: URL, cutoff: Date) -> [UsageRecord] {
        guard data.count <= 32 * 1_048_576,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let messages = obj["messages"] as? [[String: Any]] else { return [] }
        let session = obj["sessionId"] as? String ?? file.lastPathComponent
        return messages.compactMap { m in
            guard m["type"] as? String == "gemini", let t = m["tokens"] as? [String: Any],
                  let date = UsageRecord.date(m["timestamp"]), date >= cutoff else { return nil }
            let counts = geminiTokenCounts(t)
            guard counts.input + counts.output + counts.cacheRead > 0 else { return nil }
            let msgID = (m["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = (msgID?.isEmpty == false ? msgID! : Self.digest(Data("\(date.timeIntervalSince1970)|\(counts.input)|\(counts.output)|\(counts.cacheRead)".utf8)))
            return UsageRecord(id: "gemini:" + session + ":" + suffix,
                timestamp: date, tool: .gemini, model: m["model"] as? String ?? "unknown", input: counts.input,
                output: counts.output, cacheRead: counts.cacheRead, project: "Gemini CLI", session: "gemini:" + session)
        }
    }

    private func parseGeminiJSONL(file: URL, cutoff: Date) throws -> [UsageRecord] {
        struct GeminiEntry {
            var explicitID: String?
            var timestamp: Date?
            var model: String?
            var tokens: (input: Int, output: Int, cacheRead: Int)?
            var isGemini: Bool = false
        }
        var session = file.deletingPathExtension().lastPathComponent
        var order: [String] = []
        var entries: [String: GeminiEntry] = [:]
        var anonIndex = 0
        try UsageLogReader.forEachLine(at: file) { line in
            autoreleasepool {
                guard let d = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
                if let sid = (d["sessionId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty {
                    session = sid
                }
                let type = d["type"] as? String ?? ""
                if type == "session_metadata" { return }
                guard type == "gemini" || type == "message_update" else { return }
                let nested = (d["update"] as? [String: Any])
                    ?? (d["message"] as? [String: Any])
                    ?? (d["data"] as? [String: Any])
                let rawID = (d["id"] as? String) ?? (d["messageId"] as? String) ?? (nested?["id"] as? String)
                let cleanID = rawID?.trimmingCharacters(in: .whitespacesAndNewlines)
                let key: String
                if let cleanID, !cleanID.isEmpty {
                    key = "id:" + cleanID
                } else {
                    guard type == "gemini" else { return }
                    anonIndex += 1
                    key = "anon:\(anonIndex)"
                }
                if entries[key] == nil {
                    order.append(key)
                    entries[key] = GeminiEntry(explicitID: (cleanID?.isEmpty == false) ? cleanID : nil)
                }
                var entry = entries[key]!
                if type == "gemini" { entry.isGemini = true }
                if let date = UsageRecord.date(d["timestamp"] ?? nested?["timestamp"]) {
                    if entry.timestamp == nil || type == "gemini" { entry.timestamp = date }
                }
                if let model = ((d["model"] as? String) ?? (nested?["model"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !model.isEmpty {
                    entry.model = model
                }
                if let t = (d["tokens"] as? [String: Any]) ?? (nested?["tokens"] as? [String: Any]) {
                    entry.tokens = geminiTokenCounts(t)
                    entry.isGemini = true
                }
                entries[key] = entry
            }
        }
        return order.compactMap { key in
            guard let entry = entries[key], entry.isGemini, let counts = entry.tokens,
                  counts.input + counts.output + counts.cacheRead > 0,
                  let date = entry.timestamp, date >= cutoff else { return nil }
            let suffix = entry.explicitID ?? Self.digest(Data("\(date.timeIntervalSince1970)|\(counts.input)|\(counts.output)|\(counts.cacheRead)|\(key)".utf8))
            return UsageRecord(id: "gemini:" + session + ":" + suffix,
                timestamp: date, tool: .gemini, model: entry.model ?? "unknown", input: counts.input,
                output: counts.output, cacheRead: counts.cacheRead, project: "Gemini CLI", session: "gemini:" + session)
        }
    }

    private func scanAntigravity(cutoff: Date, visited: inout Set<String>, errors: inout [ToolKind: Int]) -> [UsageRecord] {
        let brainRoot = home.appendingPathComponent(".gemini/antigravity/brain")
        guard FileManager.default.fileExists(atPath: brainRoot.path) else { return [] }
        guard let conversations = try? FileManager.default.contentsOfDirectory(
            at: brainRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else {
            errors[.antigravity, default: 0] += 1
            return []
        }
        let projects = loadAntigravityProjects()
        var records: [UsageRecord] = []
        for convDir in conversations {
            let convID = convDir.lastPathComponent
            let file = convDir.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            visited.insert(file.path)
            do {
                let rv = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
                guard rv.isRegularFile == true else { continue }
                let size = rv.fileSize ?? 0, modified = rv.contentModificationDate ?? .distantPast
                guard modified >= cutoff else { continue }
                let project = projects[convID] ?? "Antigravity"
                let rows: [UsageRecord]
                if let hit = cache[file.path], hit.size == size, hit.modified == modified, hit.project == project {
                    rows = hit.records
                } else {
                    rows = try parseAntigravity(file: file, conversationID: convID, project: project, cutoff: cutoff)
                    cache[file.path] = Cached(size: size, modified: modified, project: project, records: rows)
                }
                records.append(contentsOf: rows)
            } catch {
                errors[.antigravity, default: 0] += 1
            }
        }
        return records
    }

    private func loadAntigravityProjects() -> [String: String] {
        let path = home.appendingPathComponent(".gemini/antigravity/conversation_summaries.db").path
        guard FileManager.default.fileExists(atPath: path) else { return [:] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            return [:]
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var statement: OpaquePointer?
        let sql = "SELECT conversation_id, workspace_uris FROM conversation_summaries"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }
        var projects: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = sqlite3_column_text(statement, 0),
                  let rawURIs = sqlite3_column_text(statement, 1) else { continue }
            let id = String(cString: rawID)
            let urisText = String(cString: rawURIs)
            guard let uris = (try? JSONSerialization.jsonObject(with: Data(urisText.utf8))) as? [String],
                  let first = uris.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { continue }
            let name: String
            if let url = URL(string: first), url.isFileURL {
                name = url.lastPathComponent
            } else {
                name = URL(fileURLWithPath: first).lastPathComponent
            }
            if !name.isEmpty, name != "/" {
                projects[id] = name
            }
        }
        return projects
    }

    private func parseAntigravity(file: URL, conversationID: String, project: String, cutoff: Date) throws -> [UsageRecord] {
        struct StepEntry {
            var id: String
            var timestamp: Date
            var model: String
            var input: Int
            var output: Int
            var cacheWrite: Int
            var cacheRead: Int
        }
        var order: [String] = []
        var entries: [String: StepEntry] = [:]
        try UsageLogReader.forEachLine(at: file) { line in
            // Only parse metering lines; skip USER_INPUT / GENERIC tool outputs without touching prompts.
            guard line.range(of: Self.agInputMarker) != nil
                || line.range(of: Self.agOutputMarker) != nil
                || line.range(of: Self.agCacheReadMarker) != nil
                || line.range(of: Self.agCacheCreateMarker) != nil else { return }
            autoreleasepool {
                guard let d = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let timestamp = UsageRecord.date(d["created_at"]) else { return }
                let input = Self.token(d, "input_tokens")
                let output = Self.token(d, "output_tokens")
                let cacheRead = Self.token(d, "cache_read_tokens")
                let cacheWrite = Self.token(d, "cache_creation_tokens")
                guard input + output + cacheRead + cacheWrite > 0 else { return }
                let rawModel = (d["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                // Missing model (e.g. internal CHECKPOINT compaction) retains "unknown" instead of guessing a paid tier.
                let model = (rawModel?.isEmpty == false) ? rawModel! : "unknown"
                let stepKey: String
                let recordID: String
                if let stepNum = d["step_index"] as? NSNumber, CFGetTypeID(stepNum) != CFBooleanGetTypeID() {
                    let idx = stepNum.intValue
                    stepKey = "step:\(idx)"
                    recordID = "antigravity:\(conversationID):\(idx)"
                } else {
                    let digest = Self.digest(Data("\(timestamp.timeIntervalSince1970)|\(model)|\(input)|\(output)|\(cacheWrite)|\(cacheRead)".utf8))
                    stepKey = "hash:\(digest)"
                    recordID = "antigravity:\(conversationID):\(digest)"
                }
                if entries[stepKey] == nil { order.append(stepKey) }
                entries[stepKey] = StepEntry(
                    id: recordID, timestamp: timestamp, model: model,
                    input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
            }
        }
        return order.compactMap { key in
            guard let entry = entries[key], entry.timestamp >= cutoff else { return nil }
            return UsageRecord(
                id: entry.id,
                timestamp: entry.timestamp,
                tool: .antigravity,
                model: entry.model,
                input: entry.input,
                output: entry.output,
                cacheWrite: entry.cacheWrite,
                cacheRead: entry.cacheRead,
                project: project,
                session: "antigravity:" + conversationID)
        }
    }

    private func scanOpenCode(cutoff: Date) throws -> [UsageRecord] {
        let path = home.appendingPathComponent(".local/share/opencode/opencode.db").path
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }; throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var statement: OpaquePointer?
        let sql = "SELECT id, session_id, data FROM message WHERE time_created >= ?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(cutoff.timeIntervalSince1970 * 1000))
        var result: [UsageRecord] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            defer { step = sqlite3_step(statement) }
            guard let raw = sqlite3_column_text(statement, 2), sqlite3_column_bytes(statement, 2) <= 4 * 1_048_576,
                  let d = (try? JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8))) as? [String: Any],
                  d["role"] as? String == "assistant", let tokens = d["tokens"] as? [String: Any],
                  let time = d["time"] as? [String: Any], let date = UsageRecord.date(time["completed"] ?? time["created"]) else { continue }
            let cache = tokens["cache"] as? [String: Any] ?? [:]
            let id = String(cString: sqlite3_column_text(statement, 0))
            let session = String(cString: sqlite3_column_text(statement, 1))
            // OpenCode output already contains reasoning. Its cost may be a local estimate; keep our API-equivalent meaning.
            result.append(UsageRecord(id: "opencode:" + id, timestamp: date, tool: .opencode,
                model: d["modelID"] as? String ?? "unknown", input: Self.token(tokens, "input"), output: Self.token(tokens, "output"),
                cacheWrite: Self.token(cache, "write"), cacheRead: Self.token(cache, "read"), project: "OpenCode", session: "opencode:" + session))
        }
        guard step == SQLITE_DONE else { throw CocoaError(.fileReadUnknown) }
        return result
    }

    static func token(_ obj: [String: Any], _ key: String) -> Int { UsageValueSanitizer.tokens(obj[key] as? NSNumber) }
    static func digest(_ data: Data) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        for b in SHA256.hash(data: data) {
            bytes.append(hexTable[Int(b >> 4)])
            bytes.append(hexTable[Int(b & 0x0f)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
