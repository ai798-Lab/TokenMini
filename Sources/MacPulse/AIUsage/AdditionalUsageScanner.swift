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
        var size: Int, modified: Date, records: [UsageRecord]
    }
    private let home: URL
    private var cache: [String: Cached] = [:]
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    func scanAll() -> Result {
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        var records: [UsageRecord] = []
        var seen = Set<String>(), visited = Set<String>()
        var errors: [ToolKind: Int] = [:]
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
                guard (tool == .kimi && file.lastPathComponent == fileName)
                    || (tool == .gemini && file.lastPathComponent.hasPrefix(fileName) && file.pathExtension == "json") else { continue }
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
                        let data = try Data(contentsOf: file, options: .alwaysMapped)
                        rows = tool == .kimi ? parseKimi(data, file: file, cutoff: cutoff) : parseGemini(data, file: file, cutoff: cutoff)
                        cache[file.path] = Cached(size: size, modified: modified, records: rows)
                    }
                    for row in rows where row.timestamp >= cutoff && seen.insert(row.id).inserted { records.append(row) }
                } catch { errors[tool, default: 0] += 1 }
            }
        }
        cache = cache.filter { visited.contains($0.key) }
        do { records += try scanOpenCode(cutoff: cutoff) } catch { errors[.opencode, default: 0] += 1 }
        do { records += try TraeUsageClient.cached(home: home).filter { $0.timestamp >= cutoff } }
        catch { errors[.traeWork, default: 0] += 1 }
        var statuses: [ToolSourceStatus] = [ToolKind.kimi, .gemini, .opencode].map { tool in
            let count = records.filter { $0.tool == tool }.count
            let detail = errors[tool, default: 0] > 0 ? "部分记录读取失败（\(errors[tool]!) 处）" : count > 0 ? "本地记录 · 自动更新" : "近 90 天未发现可读取用量"
            return ToolSourceStatus(tool: tool, count: count, detail: detail)
        }
        do {
            let imported = try UsageImport.load(home: home)
            records += imported.filter { $0.timestamp >= cutoff }
            for tool in ToolKind.allCases where !tool.localScanner {
                let count = records.filter { $0.tool == tool && $0.timestamp >= cutoff }.count
                statuses.append(ToolSourceStatus(tool: tool, count: count,
                    detail: tool == .traeWork ? (errors[.traeWork, default: 0] > 0 ? "同步缓存读取失败" : count > 0 ? "官方用量缓存 / 导入记录 · 在下方更新" : "可选：同步 Trae Work CN 官方用量") : count > 0 ? "已导入 · 不自动同步工具账号" : tool == .cursor ? "待导入 Cursor 用量 CSV" : "待接入 · 支持通用用量文件导入"))
            }
        } catch {
            statuses.append(ToolSourceStatus(tool: .other, detail: "导入记录读取失败：\(error.localizedDescription)"))
        }
        return Result(events: records.map(\.event), statuses: statuses)
    }

    private func parseKimi(_ data: Data, file: URL, cutoff: Date) -> [UsageRecord] {
        var rows: [UsageRecord] = []
        let parts = file.pathComponents
        let session: String = parts.firstIndex(of: "agents").map { parts[$0 - 1] }
            ?? file.deletingLastPathComponent().lastPathComponent
        // Only parse metering records, never context.append_loop_event / turn.prompt bodies.
        for line in data.split(separator: 10) where line.count <= 1_048_576 {
            guard line.range(of: Data("usage.record".utf8)) != nil || line.range(of: Data("StatusUpdate".utf8)) != nil else { continue }
            autoreleasepool {
                guard let d = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { return }
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

    private func parseGemini(_ data: Data, file: URL, cutoff: Date) -> [UsageRecord] {
        guard data.count <= 32 * 1_048_576,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let messages = obj["messages"] as? [[String: Any]] else { return [] }
        let session = obj["sessionId"] as? String ?? file.lastPathComponent
        return messages.compactMap { m in
            guard m["type"] as? String == "gemini", let t = m["tokens"] as? [String: Any],
                  let date = UsageRecord.date(m["timestamp"]), date >= cutoff else { return nil }
            let input = Self.token(t, "input"), cached = min(input, Self.token(t, "cached"))
            // Gemini thoughts are separate from output in the CLI token record.
            let output = Self.token(t, "output") + Self.token(t, "thoughts")
            return UsageRecord(id: "gemini:" + session + ":" + (m["id"] as? String ?? Self.digest(Data("\(date.timeIntervalSince1970)|\(input)|\(output)|\(cached)".utf8))),
                timestamp: date, tool: .gemini, model: m["model"] as? String ?? "unknown", input: input - cached,
                output: output, cacheRead: cached, project: "Gemini CLI", session: "gemini:" + session)
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
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
