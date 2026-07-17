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

    private struct ParsedLine {
        let timestamp: Date
        let model: String
        let inputTokens: Int       // 非缓存输入
        let cacheReadTokens: Int   // 缓存命中输入
        let outputTokens: Int
    }

    private struct FileCache {
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
            let info: Info?
        }

        struct Info: Decodable {
            let lastTokenUsage: TokenUsage?

            enum CodingKeys: String, CodingKey {
                case lastTokenUsage = "last_token_usage"
            }
        }

        struct TokenUsage: Decodable {
            let inputTokens: Double?
            let cachedInputTokens: Double?
            let outputTokens: Double?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case cachedInputTokens = "cached_input_tokens"
                case outputTokens = "output_tokens"
            }
        }
    }

    private var cache: [String: FileCache] = [:]
    private let decoder = JSONDecoder()

    func scanAll() -> [UsageEvent] {
        let cutoff = Date().addingTimeInterval(-Self.maxEventAge)
        let base = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/sessions")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base, isDirectory: &isDir), isDir.boolValue else {
            cache = [:]; return []
        }

        var newCache: [String: FileCache] = [:]
        let baseURL = URL(fileURLWithPath: base, isDirectory: true)
        guard let en = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }

        for case let url as URL in en where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            let path = url.path
            guard let rv = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  rv.isRegularFile == true else { continue }
            let size = Int64(rv.fileSize ?? 0)
            let mtime = rv.contentModificationDate ?? .distantPast
            if let hit = cache[path], hit.size == size, hit.mtime == mtime {
                newCache[path] = hit; continue
            }
            newCache[path] = parseFile(at: url, cutoff: cutoff)
        }
        cache = newCache

        var events: [UsageEvent] = []
        for (_, file) in cache {
            for e in file.events where e.timestamp >= cutoff {
                events.append(UsageEvent(
                    timestamp: e.timestamp,
                    model: e.model,
                    inputTokens: e.inputTokens,
                    outputTokens: e.outputTokens,
                    cacheCreationTokens: 0,
                    cacheCreation1hTokens: 0,
                    cacheReadTokens: e.cacheReadTokens,
                    speed: nil,
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

    private func parseFile(at url: URL, cutoff: Date) -> FileCache {
        let rv = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(rv?.fileSize ?? 0)
        let mtime = rv?.contentModificationDate ?? .distantPast
        let session = url.deletingPathExtension().lastPathComponent

        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), !data.isEmpty else {
            return FileCache(size: size, mtime: mtime, events: [], project: "unknown", session: session)
        }

        var events: [ParsedLine] = []
        var model = "gpt-5"                 // 默认;首个 turn_context 会覆盖
        var project = "unknown"

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
                if let cwd = payload.cwd, project == "unknown" { project = Self.projectName(cwd) }
            case "event_msg":
                guard payload.type == "token_count",
                      let last = payload.info?.lastTokenUsage,
                      let ts = obj.timestamp,
                      let when = self.parseTimestamp(ts) else { return }
                let input = UsageValueSanitizer.tokens(last.inputTokens)
                let cached = min(UsageValueSanitizer.tokens(last.cachedInputTokens), input)
                let output = UsageValueSanitizer.tokens(last.outputTokens)
                let nonCached = max(0, input - cached)
                guard nonCached + cached + output > 0, when >= cutoff else { return }
                events.append(ParsedLine(timestamp: when, model: model,
                                         inputTokens: nonCached, cacheReadTokens: cached,
                                         outputTokens: output))
            default: break
            }
        }

        var start = data.startIndex
        while let newline = data[start...].firstIndex(of: 0x0A) {
            if newline > start, newline - start <= Self.maxJSONLineBytes {
                autoreleasepool { handleLine(data[start..<newline]) }
            }
            start = data.index(after: newline)
        }
        if start < data.endIndex, data.endIndex - start <= Self.maxJSONLineBytes {
            autoreleasepool { handleLine(data[start..<data.endIndex]) }
        }

        return FileCache(size: size, mtime: mtime, events: events, project: project, session: session)
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
