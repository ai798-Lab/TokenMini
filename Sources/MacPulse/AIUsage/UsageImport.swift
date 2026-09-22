import Foundation
import CoreFoundation

/// Normalized imported metering only. No prompts, account names, paths or credentials are persisted.
struct UsageRecord: Codable, Sendable {
    var id: String
    var timestamp: Date
    var tool: ToolKind
    var model: String
    var input: Int
    var output: Int
    var cacheWrite: Int = 0
    var cacheRead: Int = 0
    var costUSD: Double? = nil
    var project: String = "导入用量"
    var session: String = "import"
    var event: UsageEvent {
        UsageEvent(timestamp: timestamp, model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : model, inputTokens: input, outputTokens: output,
            cacheCreationTokens: cacheWrite, cacheCreation1hTokens: 0, cacheReadTokens: cacheRead,
            speed: nil, costUSD: costUSD, sourceApp: tool.rawValue, project: project, sessionID: session)
    }
    static func date(_ value: Any?) -> Date? {
        if let n = value as? NSNumber {
            let v = n.doubleValue
            guard CFGetTypeID(n) != CFBooleanGetTypeID(), v.isFinite, v > 0 else { return nil }
            return Date(timeIntervalSince1970: v > 100_000_000_000 ? v / 1000 : v)
        }
        guard let string = value as? String else { return nil }
        return ISO8601TimestampParser.parse(string)
    }
}

enum UsageImport {
    struct ImportError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }
    static func location(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/TokenMini/usage-imports.json")
    }
    static func load(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [UsageRecord] {
        let file = location(home: home)
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([UsageRecord].self, from: Data(contentsOf: file))
    }
    static func save(_ rows: [UsageRecord], home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> Int {
        var existing = try load(home: home)
        var seen = Set(existing.map(\.id))
        let fresh = rows.filter { seen.insert($0.id).inserted }
        existing += fresh
        let file = location(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(existing).write(to: file, options: .atomic)
        return fresh.count
    }
    static func parse(_ data: Data, format: String, tool: ToolKind) throws -> [UsageRecord] {
        guard data.count <= 32 * 1_048_576 else { throw ImportError(message: "文件超过 32 MB，请分批导入。") }
        let objects: [[String: Any]]
        if format.lowercased() == "csv" {
            guard let text = String(data: data, encoding: .utf8) else { throw ImportError(message: "CSV 需要 UTF-8 编码。") }
            let table = try csv(text)
            guard let header = table.first else { throw ImportError(message: "文件为空。") }
            let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{feff}", with: "") }
            guard Set(names).count == names.count else { throw ImportError(message: "CSV 存在重复列名。") }
            objects = try table.dropFirst().enumerated().map { index, values in
                guard values.count == names.count else { throw ImportError(message: "第 \(index + 2) 行列数不正确，未导入。") }
                let row = Dictionary(uniqueKeysWithValues: zip(names, values))
                func value(_ keys: [String]) -> String? { keys.compactMap { row[$0] }.first }
                var obj: [String: Any] = [:]
                obj["timestamp"] = value(["timestamp", "Date", "date", "时间"])
                obj["model"] = value(["model", "Model", "模型"])
                let hasSeparateInput = row["Input (w/o Cache Write)"] != nil
                let numeric: [(String, [String])] = [
                    ("input", hasSeparateInput ? ["Input (w/o Cache Write)"] : ["input", "input_tokens", "Input Tokens", "Input (w/ Cache Write)"]),
                    ("output", ["output", "output_tokens", "Output Tokens"]),
                    ("cacheRead", ["cacheRead", "cache_read_tokens", "Cache Read"]),
                    ("cacheWrite", hasSeparateInput ? ["Input (w/ Cache Write)"] : ["cacheWrite", "cache_write_tokens", "Cache Write"])
                ]
                for (key, columns) in numeric {
                    if let v = value(columns), !v.isEmpty {
                        guard let n = Double(v.replacingOccurrences(of: ",", with: "")), n.isFinite else { throw ImportError(message: "第 \(index + 2) 行的 \(key) 不是数字。") }
                        obj[key] = n
                    }
                }
                // TokenTracker parseCursorCsv: inclusive input minus uncached input = cache writes.
                if hasSeparateInput, let combined = obj["cacheWrite"] as? Double, let uncached = obj["input"] as? Double {
                    obj["cacheWrite"] = max(0, combined - uncached)
                }
                if let cost = value(["costUSD", "Cost", "Cost ($)"]), !cost.isEmpty {
                    let clean = cost.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
                    if let n = Double(clean) { obj["costUSD"] = n }
                    else if !["included", "free", "-", "n/a"].contains(clean.lowercased()) {
                        throw ImportError(message: "第 \(index + 2) 行费用无法识别。费用必须是美元数字或 Included。")
                    }
                }
                obj["id"] = value(["id", "Request ID", "request_id"])
                obj["project"] = value(["project", "Project"])
                obj["session"] = value(["session", "Session"])
                return obj
            }
        } else if format.lowercased() == "json" {
            guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ImportError(message: "JSON 文件需要用量记录数组。") }
            objects = array
        } else {
            objects = try data.split(separator: 10).map { line in
                guard let obj = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { throw ImportError(message: "JSONL 每行需要一条用量记录。") }
                return obj
            }
        }
        guard !objects.isEmpty else { throw ImportError(message: "没有可导入的记录。") }
        return try objects.enumerated().map { index, obj in
            func fail(_ field: String) -> ImportError { ImportError(message: "第 \(index + 1) 条缺少或包含无效的 \(field)，整份文件未导入。") }
            guard let date = UsageRecord.date(obj["timestamp"]), date <= Date().addingTimeInterval(300),
                  let model = obj["model"] as? String, !model.trimmingCharacters(in: .whitespaces).isEmpty, model.count <= 256 else { throw fail("timestamp / model") }
            func count(_ key: String, required: Bool = false) throws -> Int {
                guard let value = obj[key] else { if required { throw fail(key) }; return 0 }
                guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                      n.doubleValue.isFinite, n.doubleValue >= 0, n.doubleValue <= Double(UsageValueSanitizer.maxTokensPerEvent),
                      n.doubleValue.rounded() == n.doubleValue else { throw fail(key) }
                return n.intValue
            }
            let input = try count("input", required: true), output = try count("output", required: true)
            let read = try count("cacheRead"), write = try count("cacheWrite")
            var cost: Double?
            if let value = obj["costUSD"] {
                guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                      n.doubleValue >= 0, n.doubleValue <= UsageValueSanitizer.maxCostPerEvent else { throw fail("costUSD") }
                cost = n.doubleValue
            }
            let project = String((obj["project"] as? String ?? "导入用量").prefix(256))
            let session = String((obj["session"] as? String ?? "import").prefix(256))
            let explicitID = (obj["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = explicitID.flatMap { $0.isEmpty ? nil : $0 } ?? "\(date.timeIntervalSince1970)|\(model)|\(input)|\(output)|\(write)|\(read)|\(project)|\(session)"
            return UsageRecord(id: tool.rawValue + ":import:" + AdditionalUsageScanner.digest(Data(identity.utf8)),
                timestamp: date, tool: tool, model: model, input: input, output: output, cacheWrite: write, cacheRead: read,
                costUSD: cost, project: project, session: tool.rawValue + ":" + session)
        }
    }

    /// RFC 4180 quoting, escaped quotes, CRLF and embedded newlines.
    static func csv(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var it = text.makeIterator(), next = it.next()
        while let c = next {
            next = it.next()
            if c == "\"" {
                if quoted && next == "\"" { field.append("\""); next = it.next() }
                else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r\n" || c == "\r") && !quoted {
                row.append(field); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = []; field = ""
            } else { field.append(c) }
        }
        guard !quoted else { throw ImportError(message: "CSV 引号未闭合。") }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
