import Foundation

/// Claude Code 会话 JSONL 扫描器,行为对齐 ccusage v18 的 data-loader:
/// 目录发现、宽松逐行解析、"messageId:requestId" 全局去重、文件按最早时间戳升序处理。
/// 线程契约:只在 UsageStore 的串行 scanQueue 上调用,内部缓存不加锁。
/// 增量策略:按文件路径缓存 (size, mtime, 解析结果);两者都没变的文件不开 FileHandle、
/// 不重复解析(热路径每文件只剩一次 stat);去重依赖跨文件全局顺序,事件列表每次从缓存重建。
final class UsageScanner: @unchecked Sendable {

    /// 事件保留窗口:界面最多看月度,超过 90 天的行在解析时直接丢弃,控内存。
    static let maxEventAge: TimeInterval = 90 * 86400

    // MARK: - 内部类型

    /// 单行解析结果。相比 UsageEvent 多保留 messageId/requestId ——
    /// 全局去重 Set 每次 scanAll 都要从缓存重建,所以缓存的是它而不是 UsageEvent。
    private struct ParsedLine {
        let timestamp: Date
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheCreation1hTokens: Int
        let cacheReadTokens: Int
        let speed: String?
        let costUSD: Double?
        let messageId: String?
        let requestId: String?
        let project: String?
    }

    private struct FileCache {
        let size: Int64
        let mtime: Date
        let lines: [ParsedLine]
        let minTimestamp: Date?      // 文件内最早事件时间,决定去重时的文件处理顺序
        let project: String
        let session: String          // 会话标识 = JSONL 文件名(不含扩展名),即 session UUID
    }

    /// 只解码计价所需字段。JSONDecoder 会跳过 message.content/tool payload 等大字段，
    /// 避免 JSONSerialization 为每一行建立完整 NSDictionary/NSArray 对象图。
    private struct ClaudeRecord: Decodable {
        let timestamp: String?
        let requestId: String?
        let costUSD: Double?
        let cwd: String?
        let message: Message?

        struct Message: Decodable {
            let id: String?
            let model: String?
            let usage: Usage?
        }

        struct Usage: Decodable {
            let inputTokens: Double?
            let outputTokens: Double?
            let cacheCreationInputTokens: Double?
            let cacheReadInputTokens: Double?
            let cacheCreation: CacheCreation?
            let speed: String?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
                case cacheCreation = "cache_creation"
                case speed
            }
        }

        struct CacheCreation: Decodable {
            let ephemeral1hInputTokens: Double?

            enum CodingKeys: String, CodingKey {
                case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
            }
        }
    }

    private var cache: [String: FileCache] = [:]
    private let decoder = JSONDecoder()
    private static let usageMarkers = ["\"usage\"", "\"input_tokens\"", "\"output_tokens\""]
        .map { Data($0.utf8) }
    private static let maxJSONLineBytes = 32 * 1024 * 1024

    // MARK: - 扫描入口

    func scanAll() -> [UsageEvent] {
        let cutoff = Date().addingTimeInterval(-Self.maxEventAge)
        var newCache: [String: FileCache] = [:]
        newCache.reserveCapacity(cache.count)

        for url in discoverFiles() {
            let path = url.path
            if newCache[path] != nil { continue }    // 多 base 重叠(如软链)时同一文件只处理一次
            guard let rv = try? url.resourceValues(
                      forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  rv.isRegularFile == true else { continue }
            let size = Int64(rv.fileSize ?? 0)
            let mtime = rv.contentModificationDate ?? .distantPast

            if let hit = cache[path], hit.size == size, hit.mtime == mtime {
                newCache[path] = hit                 // 热路径:size/mtime 都没变,零解析
                continue
            }
            let (lines, minTs) = parseFile(at: url, cutoff: cutoff)
            newCache[path] = FileCache(size: size, mtime: mtime, lines: lines,
                                       minTimestamp: minTs,
                                       project: lines.compactMap(\.project).first ?? projectName(fromPath: path),
                                       session: url.deletingPathExtension().lastPathComponent)
        }
        cache = newCache                             // 已删除的文件随整体替换自动出缓存

        // 文件按"文件内最早 timestamp"升序处理,保证同一消息出现在多个 JSONL
        // (session 被 resume/复制)时保留时间最早那份;无时间戳的文件排最后。
        let ordered = cache.sorted { a, b in
            switch (a.value.minTimestamp, b.value.minTimestamp) {
            case let (ta?, tb?): return ta != tb ? ta < tb : a.key < b.key
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.key < b.key
            }
        }

        // 去重是 keep-first + output 取组内最大值:流式写盘时同一条消息(同 messageId:requestId)
        // 会落多行累计快照,首行的 output_tokens 是极小的中间值,只保留首行会把 output
        // 少算约 30%(真实数据实测 2196/6902 组不一致、丢 306 万 output tokens)。
        // timestamp/project 等归属字段仍取首见那份(对齐 ccusage 的"最早文件定归属"语义)。
        var seenIndex: [String: Int] = [:]
        var events: [UsageEvent] = []
        events.reserveCapacity(cache.values.reduce(0) { $0 + $1.lines.count })
        for (_, file) in ordered {
            for line in file.lines {
                // 缓存驻留期间老化过 90 天界限的行在这里补刀
                guard line.timestamp >= cutoff else { continue }
                // messageId/requestId 任一缺失则不去重,直接计入(对齐 createUniqueHash)
                if let mid = line.messageId, let rid = line.requestId {
                    let hash = mid + ":" + rid
                    if let idx = seenIndex[hash] {
                        if line.outputTokens > events[idx].outputTokens {
                            events[idx].outputTokens = line.outputTokens
                        }
                        continue
                    }
                    seenIndex[hash] = events.count
                }
                events.append(UsageEvent(
                    timestamp: line.timestamp,
                    model: line.model,
                    inputTokens: line.inputTokens,
                    outputTokens: line.outputTokens,
                    cacheCreationTokens: line.cacheCreationTokens,
                    cacheCreation1hTokens: line.cacheCreation1hTokens,
                    cacheReadTokens: line.cacheReadTokens,
                    speed: line.speed,
                    costUSD: line.costUSD,
                    sourceApp: "claude",
                    project: line.project ?? file.project,
                    sessionID: file.session))
            }
        }
        return events
    }

    // MARK: - 路径与文件发现

    private func baseDirectories() -> [String] {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        var seen = Set<String>()
        var result: [String] = []

        func append(_ raw: String) {
            guard !raw.isEmpty else { return }
            let expanded = (raw as NSString).expandingTildeInPath
            let normalized = URL(fileURLWithPath: expanded).standardizedFileURL.path
            // 目录下必须存在 projects/ 子目录才算有效数据目录
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: normalized + "/projects", isDirectory: &isDir),
                  isDir.boolValue,
                  seen.insert(normalized).inserted else { return }
            result.append(normalized)
        }

        let envPaths = env["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespaces) ?? ""
        if !envPaths.isEmpty {
            // 设置了环境变量就只认它(逗号分隔多路径),即使全无效也不回退默认目录
            for part in envPaths.split(separator: ",") {
                append(part.trimmingCharacters(in: .whitespaces))
            }
            return result
        }

        let home = fm.homeDirectoryForCurrentUser.path
        let xdg = env["XDG_CONFIG_HOME"]?.trimmingCharacters(in: .whitespaces) ?? ""
        append((xdg.isEmpty ? home + "/.config" : xdg) + "/claude")  // 新版路径
        append(home + "/.claude")                                    // 旧版路径,可与新版并存
        return result
    }

    private func discoverFiles() -> [URL] {
        var files: [URL] = []
        for base in baseDirectories() {
            let projectsDir = URL(fileURLWithPath: base, isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
            // 预取 size/mtime,后面 resourceValues 直接吃枚举缓存,避免每文件二次 stat
            guard let enumerator = FileManager.default.enumerator(
                at: projectsDir,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                files.append(url)
            }
        }
        return files
    }

    /// 项目名 = 路径里 "projects" 后第一段目录名(对齐 extractProjectFromPath)
    private func projectName(fromPath path: String) -> String {
        let segments = path.split(separator: "/")
        guard let i = segments.firstIndex(of: "projects"), i + 1 < segments.count else {
            return "unknown"
        }
        let name = segments[i + 1].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "unknown" : name
    }

    // MARK: - 逐行流式解析

    /// 文件用只读映射遍历，不把 1.6GB 会话库反复拷进 malloc 脏页；
    /// Data 的映射页由系统文件缓存管理，逐行仍只解码计价相关记录。
    private func parseFile(at url: URL, cutoff: Date) -> (lines: [ParsedLine], minTimestamp: Date?) {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), !data.isEmpty else {
            return ([], nil)
        }

        var lines: [ParsedLine] = []
        var minTs: Date?

        func consume(_ lineData: Data) {
            guard !lineData.isEmpty, lineData.count <= Self.maxJSONLineBytes,
                  Self.usageMarkers.allSatisfy({ lineData.range(of: $0) != nil }),
                  let line = parseLine(lineData, cutoff: cutoff) else { return }
            if minTs == nil || line.timestamp < minTs! { minTs = line.timestamp }
            lines.append(line)
        }

        var start = data.startIndex
        while let newline = data[start...].firstIndex(of: 0x0A) {
            if newline > start, newline - start <= Self.maxJSONLineBytes {
                autoreleasepool { consume(data[start..<newline]) }
            }
            start = data.index(after: newline)
        }
        if start < data.endIndex, data.endIndex - start <= Self.maxJSONLineBytes {
            autoreleasepool { consume(data[start..<data.endIndex]) }
        }
        return (lines, minTs)
    }

    /// 宽松解析:必需 timestamp + message.usage.input_tokens/output_tokens 为数字,
    /// 其余字段缺省;任何一步失败都静默跳过该行(user/summary 行天然没有 usage,靠这里滤掉)。
    private func parseLine(_ data: Data, cutoff: Date) -> ParsedLine? {
        guard let record = try? decoder.decode(ClaudeRecord.self, from: data),
              let tsString = record.timestamp,
              let timestamp = parseTimestamp(tsString),
              let message = record.message,
              let usage = message.usage,
              let input = usage.inputTokens,
              let output = usage.outputTokens
        else { return nil }

        guard timestamp >= cutoff else { return nil }

        let model = message.model ?? "unknown"
        guard model != "<synthetic>" else { return nil }           // Claude Code 合成的占位消息

        // usage.cache_creation 是 {ephemeral_1h_input_tokens, ephemeral_5m_input_tokens} 明细;
        // 1h TTL 写入价是 2x 输入价(5m 是 1.25x),实测 Claude Code 的缓存写入以 1h 为主,
        // 不拆开会把费用低估约 15%。明细缺失(老版本)时按 0 处理,全部落 5m 价。
        return ParsedLine(
            timestamp: timestamp,
            model: model,
            inputTokens: UsageValueSanitizer.tokens(input),
            outputTokens: UsageValueSanitizer.tokens(output),
            cacheCreationTokens: UsageValueSanitizer.tokens(usage.cacheCreationInputTokens),
            cacheCreation1hTokens: UsageValueSanitizer.tokens(usage.cacheCreation?.ephemeral1hInputTokens),
            cacheReadTokens: UsageValueSanitizer.tokens(usage.cacheReadInputTokens),
            speed: usage.speed,
            costUSD: UsageValueSanitizer.cost(record.costUSD),
            messageId: message.id,
            requestId: record.requestId,
            project: Self.projectName(fromCWD: record.cwd))
    }

    private static func projectName(fromCWD cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = (cwd as NSString).lastPathComponent.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func parseTimestamp(_ s: String) -> Date? {
        ISO8601TimestampParser.parse(s)
    }
}
