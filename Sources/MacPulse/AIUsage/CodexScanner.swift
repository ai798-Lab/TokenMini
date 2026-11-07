import Foundation

/// Codex CLI 会话 JSONL 扫描器。数据源:~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl。
/// 每文件是一个会话,逐行事件;token 在 type=event_msg 且 payload.type=token_count 的事件里。
///
/// 关键解析规则(经本机 190M token 实测校准)——
/// - 用每个 token_count 的 `last_token_usage`(本轮增量),不用 `total_token_usage`(累计快照,逐行求和会重复计数)。
/// - `input_tokens` 含 `cached_input_tokens`(是子集不是相加):非缓存输入 = input − cached,按全价;cached 按缓存读价。
/// - `output_tokens` 已含 reasoning,整体按输出价。
/// - 模型取最近一次 turn_context.payload.model(会话内可能切换);项目取 session_meta/turn_context 的 cwd。
///
/// 线程契约:只在 UsageStore 的串行 scanQueue 上调用。
final class CodexScanner: @unchecked Sendable {
    static let maxEventAge: TimeInterval = 90 * 86400

    private struct ParsedLine: Codable {
        let timestamp: Date
        let model: String
        let inputTokens: Int       // 非缓存输入
        let cacheReadTokens: Int   // 缓存命中输入
        let outputTokens: Int
        let cacheWriteTokens: Int
        let speed: String?
        let identity: String
    }

    private struct FileCache: Codable {
        let size: Int64
        let mtime: Date
        let events: [ParsedLine]
        let project: String
        let session: String          // 会话标识 = rollout 文件名(不含扩展名)
    }

    /// 只解码扫描所需字段，跳过 rollout 中可能很大的消息正文和工具输出。
    private struct CodexRecord: Decodable {
        let timestamp: String?
        let type: String?
        let payload: Payload?

        struct Payload: Decodable {
            let type: String?
            let cwd: String?
            let model: String?
            let service_tier: String?
            let info: Info?
        }

        struct Info: Decodable {
            let lastTokenUsage: TokenUsage?
            let totalTokenUsage: TokenUsage?

            enum CodingKeys: String, CodingKey {
                case lastTokenUsage = "last_token_usage"
                case totalTokenUsage = "total_token_usage"
            }
        }

        struct TokenUsage: Decodable, Equatable {
            let inputTokens: Double?
            let cachedInputTokens: Double?
            let outputTokens: Double?
            let cacheWriteTokens: Double?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case cachedInputTokens = "cached_input_tokens"
                case outputTokens = "output_tokens"
                case cacheWriteTokens = "cache_write_input_tokens"
            }
        }
    }

    private var cache: [String: FileCache] = [:]
    private let decoder = JSONDecoder()

    private let baseDirectories: [URL]
    private let ledgerURL: URL?
    private var loadedLedger = false
    private var ledgerUnreadable = false
    private(set) var historyPersistenceFailed = false
    init(baseDirectories: [URL]? = nil, ledgerURL: URL? = nil) {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex"
        self.baseDirectories = baseDirectories ?? ["sessions", "archived_sessions"].map { URL(fileURLWithPath: home).appendingPathComponent($0) }
        self.ledgerURL = ledgerURL ?? (baseDirectories == nil ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TokenMini/metering/codex-v1.plist") : nil)
    }

    private(set) var readFailures = 0
    private(set) var compressedFiles = 0

    func scanAll(now: Date = Date()) -> [UsageEvent] {
        if !loadedLedger {
            loadedLedger = true
            if let ledgerURL, FileManager.default.fileExists(atPath: ledgerURL.path) {
                do { cache = try PropertyListDecoder().decode([String: FileCache].self, from: Data(contentsOf: ledgerURL)) }
                catch { historyPersistenceFailed = true; ledgerUnreadable = true }
            }
        }
        let cutoff = now.addingTimeInterval(-Self.maxEventAge)
        readFailures = 0
        compressedFiles = 0
        // Metering is an independent local ledger. Source rotation, compaction or cleanup
        // must never retract previously observed usage. UI still selects the last 90 days.
        var newCache = cache
        var changed = false
        for baseURL in baseDirectories {
        guard let en = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { continue }

        for case let url as URL in en where Self.isRollout(url) {
            let path = url.path
            if url.pathExtension == "zst" { compressedFiles += 1 }
            guard let rv = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  rv.isRegularFile == true else { continue }
            let size = Int64(rv.fileSize ?? 0)
            let mtime = rv.contentModificationDate ?? .distantPast
            if let hit = cache[path], hit.size == size, hit.mtime == mtime {
                newCache[path] = hit; continue
            }
            do {
                let parsed = try parseFile(at: url, cutoff: cutoff)
                var merged = parsed.events
                if let previous = cache[path] {
                    let ids = Set(merged.map(\.identity))
                    merged.append(contentsOf: previous.events.filter { !ids.contains($0.identity) })
                }
                newCache[path] = FileCache(size: parsed.size, mtime: parsed.mtime, events: merged,
                    project: parsed.project, session: parsed.session)
                changed = true
            }
            catch {
                readFailures += 1
                // Keep last verified usage during an interrupted compression/write.
                if let previous = cache[path] { newCache[path] = previous }
            }
        }
        }
        cache = newCache
        if changed || historyPersistenceFailed, let ledgerURL, !ledgerUnreadable {
            do {
                let directory = ledgerURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
                try encoder.encode(cache).write(to: ledgerURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ledgerURL.path)
                historyPersistenceFailed = false
            } catch { historyPersistenceFailed = true }
        }

        var events: [UsageEvent] = []
        var seen = Set<String>()
        for (_, file) in cache.sorted(by: { $0.key < $1.key }) {
            for e in file.events where e.timestamp >= cutoff {
                guard seen.insert(file.session + "|" + e.identity).inserted else { continue }
                events.append(UsageEvent(
                    timestamp: e.timestamp,
                    model: e.model,
                    inputTokens: e.inputTokens,
                    outputTokens: e.outputTokens,
                    cacheCreationTokens: e.cacheWriteTokens,
                    cacheCreation1hTokens: 0,
                    cacheReadTokens: e.cacheReadTokens,
                    speed: e.speed,
                    costUSD: nil,
                    sourceApp: "codex",
                    project: file.project,
                    sessionID: file.session))
            }
        }
        return events
    }

    // 只对可能含目标事件的行做 JSON 解析:含这些标记之一才解析,跳过巨大的 message 行
    private static let markers: [Data] = ["token_count", "turn_context", "session_meta"].map { Data($0.utf8) }
    private static let maxJSONLineBytes = 32 * 1024 * 1024

    private func parseFile(at url: URL, cutoff: Date) throws -> FileCache {
        let rv = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(rv?.fileSize ?? 0)
        let mtime = rv?.contentModificationDate ?? .distantPast
        let session = Self.sessionName(url)

        var events: [ParsedLine] = []
        var model = "unknown"                 // 默认;首个 turn_context 会覆盖
        var project = "unknown"
        var speed: String?
        var previousTotal: CodexRecord.TokenUsage?

        func handleLine(_ data: Data) {
            guard data.count <= Self.maxJSONLineBytes,
                  Self.markers.contains(where: { data.range(of: $0) != nil }) else { return }
            guard let obj = try? decoder.decode(CodexRecord.self, from: data),
                  let type = obj.type,
                  let payload = obj.payload else { return }
            switch type {
            case "session_meta":
                if let cwd = payload.cwd { project = Self.projectName(cwd) }
            case "turn_context":
                if let m = payload.model, !m.isEmpty { model = m }
                speed = ["fast", "priority"].contains(payload.service_tier ?? "") ? "fast" : nil
                if let cwd = payload.cwd, project == "unknown" { project = Self.projectName(cwd) }
            case "event_msg":
                guard payload.type == "token_count",
                      let last = payload.info?.lastTokenUsage,
                      let ts = obj.timestamp,
                      let when = self.parseTimestamp(ts) else { return }
                if let total = payload.info?.totalTokenUsage {
                    if previousTotal == total { return }
                    previousTotal = total
                }
                let input = UsageValueSanitizer.tokens(last.inputTokens)
                let cached = min(UsageValueSanitizer.tokens(last.cachedInputTokens), input)
                let output = UsageValueSanitizer.tokens(last.outputTokens)
                let write = min(UsageValueSanitizer.tokens(last.cacheWriteTokens), input - cached)
                let nonCached = max(0, input - cached - write)
                guard nonCached + cached + write + output > 0, when >= cutoff else { return }
                events.append(ParsedLine(timestamp: when, model: model,
                                         inputTokens: nonCached, cacheReadTokens: cached,
                                         outputTokens: output, cacheWriteTokens: write, speed: speed,
                                         identity: "\(ts)|\(model)|\(input)|\(cached)|\(write)|\(output)"))
            default: break
            }
        }

        try UsageLogReader.forEachLine(at: url) { data in
            autoreleasepool { handleLine(data) }
        }

        return FileCache(size: size, mtime: mtime, events: events, project: project, session: session)
    }

    static func isRollout(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("rollout-") &&
            (url.lastPathComponent.hasSuffix(".jsonl") || url.lastPathComponent.hasSuffix(".jsonl.zst"))
    }

    static func sessionName(_ url: URL) -> String {
        let plain = url.pathExtension == "zst" ? url.deletingPathExtension() : url
        return plain.deletingPathExtension().lastPathComponent
    }

    /// 项目名 = cwd 的最后一段目录名(与 Claude 的项目维度口径对齐为人类可读名)
    private static func projectName(_ cwd: String) -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "unknown" : name
    }

    private func parseTimestamp(_ s: String) -> Date? {
        ISO8601TimestampParser.parse(s)
    }
}
