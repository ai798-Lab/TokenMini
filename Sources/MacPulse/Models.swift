import Foundation

// MARK: - 系统监控快照类型

struct CPUSnapshot: Sendable {
    var totalUsage: Double = 0       // 0.0 ~ 1.0
    var systemUsage: Double = 0
    var userUsage: Double = 0
    var perCore: [Double] = []       // 每核心 0.0 ~ 1.0
}

struct MemorySnapshot: Sendable {
    var total: UInt64 = 0            // 字节
    var used: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var free: UInt64 = 0
    var pressure: Double = 0         // 0=正常、0.85=警告、1=危急(来自 memorystatus)
    var usageRatio: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct NetworkSnapshot: Sendable {
    var rxPerSec: Double = 0         // 字节/秒
    var txPerSec: Double = 0
}

struct DiskSnapshot: Sendable {
    var readPerSec: Double = 0       // 字节/秒
    var writePerSec: Double = 0
}

struct TopProcess: Identifiable, Sendable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let cpuPercent: Double           // 0 ~ 100*核心数
    let memoryBytes: UInt64
}

/// 磁盘可用空间(容量维度,区别于 DiskSnapshot 的读写速率)
struct DiskSpaceSnapshot: Sendable {
    var total: UInt64 = 0            // 字节
    var free: UInt64 = 0
    var used: UInt64 { total > free ? total - free : 0 }
    var usedRatio: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// 电池状态(笔记本);台式机 present = false
struct BatterySnapshot: Sendable {
    var present: Bool = false
    var currentPercent: Int?         // 当前电量 0~100
    var healthPercent: Int?          // 健康度 = MaxCapacity(Apple Silicon 已是百分比)
    var cycleCount: Int?
    var temperatureC: Double?
    var charging: Bool = false
    var externalPower: Bool = false  // 是否接了电源
}

struct FanReading: Identifiable, Sendable {
    var id: Int { index }
    let index: Int
    let currentRPM: Double
    let maxRPM: Double
}

struct SensorSnapshot: Sendable {
    var cpuTemp: Double?             // 摄氏度,CPU die 平均
    var gpuTemp: Double?
    var fans: [FanReading] = []
}

// MARK: - AI 用量类型

/// 单条 API 调用的 token 用量(来自 Claude Code / Codex 的本地会话 JSONL)
struct UsageEvent: Sendable {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    /// var:流式写盘时同一条消息会落多行累计快照,去重时用组内最大值原地修正
    var outputTokens: Int
    let cacheCreationTokens: Int     // 5m + 1h 总量
    let cacheCreation1hTokens: Int   // 其中 1h TTL 部分(写入价 2x 而非 1.25x)
    let cacheReadTokens: Int
    let speed: String?               // "fast" 时费用要乘模型的 fast 倍率
    let costUSD: Double?             // JSONL 自带的费用(如有),否则由 PricingTable 计算
    let sourceApp: String            // "claude" / "codex"
    let project: String              // 项目目录名
    let sessionID: String            // 会话标识(JSONL 文件/rollout 名),供会话维度与 Top N
}

/// 从本地会话事件得到的最近 AI 活动身份。它是“最近观测到”,不是对运行中进程的猜测。
struct RecentAIActivity: Sendable, Equatable {
    let tool: ToolKind
    let model: String
    let timestamp: Date

    /// 会话扫描每分钟刷新;只有 3 分钟内的事件才能称为“正在使用”。
    func isCurrent(now: Date) -> Bool {
        now.timeIntervalSince(timestamp) < 3 * 60
    }

    func statusLabel(now: Date) -> String {
        let age = max(0, now.timeIntervalSince(timestamp))
        if age < 3 * 60 { return "正在使用" }
        if age < 60 * 60 { return "最近使用 · \(max(1, Int(age / 60)))分钟前" }
        if age < 24 * 60 * 60 { return "最近使用 · \(Int(age / 3600))小时前" }
        return "最近使用 · \(Int(age / 86400))天前"
    }
}

/// 把 JSONL 里的 provider/日期/内部后缀模型名转成灵动岛和 UI 可直接阅读的名称。
enum ModelName {
    static func display(_ raw: String) -> String {
        let normalized = PricingTable.normalize(raw)
        guard !normalized.isEmpty, normalized != "unknown" else { return "模型未知" }

        if normalized.hasPrefix("claude-") {
            return familyName(String(normalized.dropFirst("claude-".count)))
        }
        if normalized.hasPrefix("gpt-") {
            let parts = String(normalized.dropFirst("gpt-".count)).split(separator: "-").map(String.init)
            guard let version = parts.first else { return "GPT" }
            let suffix = parts.dropFirst().map { $0.capitalized }.joined(separator: " ")
            return suffix.isEmpty ? "GPT-\(version)" : "GPT-\(version) \(suffix)"
        }
        if normalized.hasPrefix("gemini-") {
            let tail = String(normalized.dropFirst("gemini-".count))
            return "Gemini " + familyName(tail)
        }
        if normalized.hasPrefix("codex-") {
            return "Codex " + words(String(normalized.dropFirst("codex-".count)))
        }
        if normalized.hasPrefix("o3-") || normalized.hasPrefix("o4-") {
            return normalized.replacingOccurrences(of: "-", with: " ")
        }
        return words(normalized)
    }

    private static func familyName(_ value: String) -> String {
        let parts = value.split(separator: "-").map(String.init)
        guard let family = parts.first else { return words(value) }
        var version: [String] = []
        var suffix: [String] = []
        for part in parts.dropFirst() {
            if suffix.isEmpty, part.allSatisfy(\.isNumber) { version.append(part) }
            else { suffix.append(part.capitalized) }
        }
        return ([family.capitalized]
                + (version.isEmpty ? [] : [version.joined(separator: ".")])
                + suffix).joined(separator: " ")
    }

    private static func words(_ value: String) -> String {
        value.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}

/// 灵动岛的陪伴语气。情绪只改变措辞与点缀色，不替代模型、额度等事实信息。
enum CompanionTone: Sendable, Equatable {
    case calm, warm, caution, urgent
}

enum CompanionHealth: Sendable, Equatable {
    case good, warn, critical
}

struct CompanionMoment: Sendable, Equatable {
    let text: String
    let icon: String
    let tone: CompanionTone
}

/// 把“正在创作 / 夜间陪伴 / 额度吃紧 / 电脑疲惫”收敛成一句克制的陪伴话术。
/// 优先级刻意把健康和额度风险放前面，避免温柔文案掩盖真正需要处理的事。
enum CompanionMood {
    static func resolve(activity: RecentAIActivity?, quotaUsedPercent: Double?,
                        quotaReset: Bool, health: CompanionHealth,
                        now: Date, calendar: Calendar = .current) -> CompanionMoment {
        if health == .critical {
            return CompanionMoment(text: "电脑也累了，先照顾一下它",
                                   icon: "heart.slash.fill", tone: .urgent)
        }
        if health == .warn {
            return CompanionMoment(text: "电脑有点忙，慢一点也没关系",
                                   icon: "heart.fill", tone: .caution)
        }
        if let used = quotaUsedPercent, used >= 85 {
            return CompanionMoment(text: "快到边了，我替你盯着",
                                   icon: "eye.fill", tone: .urgent)
        }
        if let used = quotaUsedPercent, used >= 60 {
            return CompanionMoment(text: "进入后半程，把火力留给重点",
                                   icon: "scope", tone: .caution)
        }

        if let activity, activity.isCurrent(now: now) {
            let hour = calendar.component(.hour, from: now)
            if hour >= 23 || hour < 6 {
                return CompanionMoment(text: "夜深了，我陪你写完这一段",
                                       icon: "moon.stars.fill", tone: .warm)
            }
            return CompanionMoment(text: "状态在线，放心往前写",
                                   icon: "sparkles", tone: .warm)
        }
        if let activity, now.timeIntervalSince(activity.timestamp) < 60 * 60 {
            return CompanionMoment(text: "刚才的思路还热着",
                                   icon: "flame.fill", tone: .warm)
        }
        if quotaReset {
            return CompanionMoment(text: "余量满满，等你开工",
                                   icon: "battery.100percent", tone: .calm)
        }
        return CompanionMoment(text: "我在这儿，等你继续",
                               icon: "heart.fill", tone: .calm)
    }
}

struct VibeGreeting: Sendable, Equatable {
    let title: String
    let subtitle: String
}

/// 每日第一次 AI 活动的问候。模型身份带进问候里，让提醒像“搭档已就位”。
enum VibeCopy {
    static func greeting(at date: Date, activity: RecentAIActivity?,
                         calendar: Calendar = .current) -> VibeGreeting {
        let hour = calendar.component(.hour, from: date)
        let identity: String
        if let activity {
            let tool = activity.tool == .claude ? "Claude" : activity.tool.label
            identity = "\(tool) · \(ModelName.display(activity.model))"
        } else {
            identity = "AI 搭档"
        }

        if hour >= 5 && hour < 11 {
            return VibeGreeting(title: "早呀，慢慢进入状态 ☕",
                                subtitle: "\(identity) 已就位，今天也一起顺顺利利")
        }
        if hour >= 11 && hour < 18 {
            return VibeGreeting(title: "开工啦，灵感上线 ✨",
                                subtitle: "\(identity) 已就位，今天也一起顺顺利利")
        }
        if hour >= 18 && hour < 23 {
            return VibeGreeting(title: "晚上好，一起写一会儿",
                                subtitle: "\(identity) 已就位，慢慢写，不着急")
        }
        return VibeGreeting(title: "夜深了，我陪你写一段",
                            subtitle: "\(identity) 已就位，写完记得早点休息")
    }
}

/// 一个模型的价格,单位:美元 / 1M token。
/// above200k*:部分模型(Sonnet 4.5/4、Gemini Pro 系)单条请求超过 200K token 的部分用更高单价。
/// fullRequest*:GPT-5.6 等模型在输入越过阈值后,整次请求分别乘输入/输出倍率。
/// cacheWrite1hPerMTok:1 小时 TTL 缓存写入价(Anthropic = 2x 输入价);
/// Claude Code 实际以 1h 缓存为主,漏掉会系统性低估约 15%。
struct ModelPricing: Sendable {
    let inputPerMTok: Double
    let outputPerMTok: Double
    let cacheWritePerMTok: Double        // 5 分钟 TTL 写入价(1.25x 输入价)
    let cacheReadPerMTok: Double
    var cacheWrite1hPerMTok: Double? = nil
    var above200kInputPerMTok: Double? = nil
    var above200kOutputPerMTok: Double? = nil
    var above200kCacheReadPerMTok: Double? = nil
    var fullRequestThreshold: Int? = nil
    var fullRequestInputMultiplier: Double = 1
    var fullRequestOutputMultiplier: Double = 1

    static let tierThreshold = 200_000

    func cost(input: Int, output: Int, cacheWrite: Int, cacheWrite1h: Int, cacheRead: Int) -> Double {
        let b = breakdown(input: input, output: output, cacheWrite: cacheWrite,
                          cacheWrite1h: cacheWrite1h, cacheRead: cacheRead)
        return b.total
    }

    /// 四分量成本(美元)。缓存写内部按 5m/1h 分档折叠成一个数。
    /// 供监控台"按 token 类型堆叠/筛选"和"缓存已省额"直接取用,不必二次查价。
    func breakdown(input: Int, output: Int, cacheWrite: Int, cacheWrite1h: Int, cacheRead: Int) -> CostBreakdown {
        func tiered(_ n: Int, _ base: Double, _ above: Double?) -> Double {
            guard n > 0 else { return 0 }
            guard let above, n > Self.tierThreshold else { return Double(n) * base }
            let below = Double(Self.tierThreshold)
            return below * base + Double(n - Self.tierThreshold) * above
        }
        let safeInput = max(input, 0), safeOutput = max(output, 0)
        let safeWrite = max(cacheWrite, 0), safeRead = max(cacheRead, 0)
        // cacheWrite 是 5m+1h 总量;1h 明细缺失(老版本 JSONL)时全部按 5m 价
        let write1h = min(max(cacheWrite1h, 0), safeWrite)
        let write5m = safeWrite - write1h
        let promptTokens = Double(safeInput) + Double(safeWrite) + Double(safeRead)
        let isFullRequestTier = fullRequestThreshold.map { promptTokens > Double($0) } ?? false
        let inputMultiplier = isFullRequestTier ? fullRequestInputMultiplier : 1
        let outputMultiplier = isFullRequestTier ? fullRequestOutputMultiplier : 1
        return CostBreakdown(
            input: tiered(safeInput, inputPerMTok, above200kInputPerMTok) * inputMultiplier / 1_000_000,
            output: tiered(safeOutput, outputPerMTok, above200kOutputPerMTok) * outputMultiplier / 1_000_000,
            cacheWrite: (Double(write5m) * cacheWritePerMTok
                + Double(write1h) * (cacheWrite1hPerMTok ?? cacheWritePerMTok)) * inputMultiplier / 1_000_000,
            cacheRead: tiered(safeRead, cacheReadPerMTok, above200kCacheReadPerMTok)
                * inputMultiplier / 1_000_000)
    }

    /// 缓存读若按满价输入计,与实际缓存读价之差 = 缓存省下的钱(美元)
    func cacheSaved(cacheRead: Int) -> Double {
        guard cacheRead > 0 else { return 0 }
        let full = Double(cacheRead) * inputPerMTok / 1_000_000
        let actual = Double(cacheRead) * cacheReadPerMTok / 1_000_000
        return max(0, full - actual)
    }
}

/// JSONL 是用户目录里的外部输入。统一夹取负数、NaN 和异常大值,避免总计倒扣或整数溢出。
enum UsageValueSanitizer {
    static let maxTokensPerEvent = 1_000_000_000
    static let maxCostPerEvent = 1_000_000.0

    static func tokens(_ number: NSNumber?) -> Int {
        tokens(number?.doubleValue)
    }

    static func tokens(_ value: Double?) -> Int {
        guard let value, value.isFinite, value > 0 else { return 0 }
        return Int(min(value.rounded(.towardZero), Double(maxTokensPerEvent)))
    }

    static func cost(_ number: NSNumber?) -> Double? {
        cost(number?.doubleValue)
    }

    static func cost(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return min(value, maxCostPerEvent)
    }
}

/// 会话 JSONL 的时间戳热路径解析器。ISO8601DateFormatter 在逐行扫描数万条记录时
/// 会制造大量 CoreFoundation 临时小对象；这里用纯数值解析支持会话实际出现的
/// `YYYY-MM-DDTHH:mm:ss[.fraction](Z|±HH:mm)`，避免冷扫后的 GB 级 malloc 空页。
enum ISO8601TimestampParser {
    static func parse(_ value: String) -> Date? {
        if let date = value.utf8.withContiguousStorageIfAvailable({ parseBytes($0) }) {
            return date
        }
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { parseBytes($0) }
    }

    private static func parseBytes(_ b: UnsafeBufferPointer<UInt8>) -> Date? {
        guard b.count >= 20,
              b[4] == 45, b[7] == 45,
              b[10] == 84 || b[10] == 116 || b[10] == 32,
              b[13] == 58, b[16] == 58 else { return nil }

        @inline(__always) func digit(_ index: Int) -> Int? {
            let byte = b[index]
            return byte >= 48 && byte <= 57 ? Int(byte - 48) : nil
        }
        @inline(__always) func two(_ index: Int) -> Int? {
            guard let a = digit(index), let c = digit(index + 1) else { return nil }
            return a * 10 + c
        }

        guard let y0 = digit(0), let y1 = digit(1), let y2 = digit(2), let y3 = digit(3),
              let month = two(5), let day = two(8), let hour = two(11),
              let minute = two(14), let second = two(17) else { return nil }
        let year = y0 * 1000 + y1 * 100 + y2 * 10 + y3
        guard (1...12).contains(month), (0...23).contains(hour),
              (0...59).contains(minute), (0...60).contains(second) else { return nil }

        let leap = year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
        let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day >= 1, day <= monthDays[month - 1] else { return nil }

        var index = 19
        var fraction = 0.0
        if index < b.count, b[index] == 46 {
            index += 1
            var scale = 0.1
            var foundDigit = false
            while index < b.count, let d = digit(index) {
                foundDigit = true
                fraction += Double(d) * scale
                scale *= 0.1
                index += 1
            }
            guard foundDigit else { return nil }
        }

        var offsetSeconds = 0
        guard index < b.count else { return nil }
        if b[index] == 90 || b[index] == 122 { // Z/z
            index += 1
        } else if b[index] == 43 || b[index] == 45 { // + / -
            let sign = b[index] == 43 ? 1 : -1
            index += 1
            guard index + 1 < b.count, let tzHour = two(index), tzHour <= 23 else { return nil }
            index += 2
            if index < b.count, b[index] == 58 { index += 1 }
            guard index + 1 < b.count, let tzMinute = two(index), tzMinute <= 59 else { return nil }
            index += 2
            offsetSeconds = sign * (tzHour * 3600 + tzMinute * 60)
        } else {
            return nil
        }
        guard index == b.count else { return nil }

        // Howard Hinnant 的 civil-date 算法：公历日期 -> 1970-01-01 起的天数。
        var adjustedYear = year
        if month <= 2 { adjustedYear -= 1 }
        let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
        let yearOfEra = adjustedYear - era * 400
        let adjustedMonth = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * adjustedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let daysSinceEpoch = era * 146_097 + dayOfEra - 719_468
        let leapSecond = second == 60 ? 1 : 0
        let wholeSeconds = daysSinceEpoch * 86_400 + hour * 3600 + minute * 60
            + min(second, 59) + leapSecond - offsetSeconds
        return Date(timeIntervalSince1970: Double(wholeSeconds) + fraction)
    }
}

/// 聚合结果:一段时间内的用量汇总
struct UsagePeriodSummary: Sendable {
    var totalCostUSD: Double = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var eventCount: Int = 0
    var byModel: [String: ModelUsage] = [:]

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
}

struct ModelUsage: Sendable {
    var costUSD: Double = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var eventCount: Int = 0
}

/// 按天聚合(用于趋势图)
struct DailyUsage: Identifiable, Sendable {
    var id: String { day }
    let day: String                  // "2026-07-06"(本地时区)
    let costUSD: Double
    let totalTokens: Int
}

// MARK: - 社区排行榜类型

/// 排行榜只上传按天汇总后的数值，不包含会话正文、项目名、路径或模型明细。
enum RankingMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case tokens, cost
    var id: String { rawValue }
    var label: String { self == .tokens ? "Token 消耗" : "API 等价费用" }
}

struct RankingEntry: Codable, Identifiable, Sendable, Equatable {
    var id: String { "\(rank)-\(name)" }
    let rank: Int
    let name: String
    let value: Int64
}

struct RankingListResponse: Codable, Sendable, Equatable {
    let metric: RankingMetric
    let period: String
    let periodStart: String
    let entries: [RankingEntry]
}

struct RankingProfile: Codable, Sendable, Equatable {
    let id: String
    let nickname: String
    var displayMode: String
    let joinedAt: String

    var displayedName: String {
        displayMode == "public" ? nickname : Self.masked(nickname)
    }

    static func masked(_ raw: String) -> String {
        let characters = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard characters.count > 1, let last = characters.last else { return "＊＊＊" }
        return "＊＊＊\(last)"
    }
}

struct RankingStanding: Codable, Sendable, Equatable {
    let rank: Int?
    let value: Int64
}

struct RankingMeResponse: Codable, Sendable, Equatable {
    var profile: RankingProfile
    let periodStart: String
    let tokens: RankingStanding
    let cost: RankingStanding
}

struct RankingDailyAggregate: Codable, Sendable, Equatable {
    let localDay: String
    let totalTokens: Int64
    let estimatedCostMicroUSD: Int64
    let pricingVersion: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case localDay = "local_day"
        case totalTokens = "total_tokens"
        case estimatedCostMicroUSD = "estimated_cost_micro_usd"
        case pricingVersion = "pricing_version"
        case appVersion = "app_version"
    }
}

struct RankingConfigResponse: Codable, Sendable {
    let googleDesktopClientID: String?
    let googleWebClientID: String?
    let authReady: Bool

    enum CodingKeys: String, CodingKey {
        case googleDesktopClientID = "google_desktop_client_id"
        case googleWebClientID = "google_web_client_id"
        case authReady = "auth_ready"
    }
}

struct RankingAuthResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let profile: RankingProfile
}

struct RankingRefreshResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

// MARK: - 通用工具

enum ByteFormat {
    /// 1234567 -> "1.2 MB";速率场景外部自行拼 "/s"。网络/磁盘速率用 1000 进制(平台惯例)。
    static func string(_ bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = bytes
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        return i == 0 ? String(format: "%.0f %@", v, units[i]) : String(format: "%.1f %@", v, units[i])
    }

    static func string(_ bytes: UInt64) -> String { string(Double(bytes)) }

    /// 内存量专用:1024 进制(与活动监视器/硬件规格一致,64GB 机器显示 64 GB 而不是 68.7 GB)
    static func memory(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(bytes)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? String(format: "%.0f %@", v, units[i]) : String(format: "%.1f %@", v, units[i])
    }

    /// token 数量:12_345_678 -> "12.3M"
    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
        return "\(n)"
    }
}

// MARK: - 垃圾清理类型

/// 可清理类目。每个类目只对应「可再生、当前不用」的缓存目录,
/// 绝不含文档/偏好设置/应用数据/pnpm store(硬链接源)等重要内容。
enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case trash          // ~/.Trash
    case appCaches      // ~/Library/Caches(应用可再生缓存,含浏览器/pip/homebrew/playwright 等)
    case userLogs       // ~/Library/Logs
    case devCaches      // ~/.npm/_cacache + Xcode DerivedData + iOS DeviceSupport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trash: return "废纸篓"
        case .appCaches: return "应用缓存"
        case .userLogs: return "用户日志"
        case .devCaches: return "开发者缓存"
        }
    }

    var subtitle: String {
        switch self {
        case .trash: return "已丢进废纸篓的文件"
        case .appCaches: return "应用可再生缓存,删后自动重建(建议先退出常用应用)"
        case .userLogs: return "历史日志,删除不影响运行"
        case .devCaches: return "npm / Xcode 派生数据,下次构建自动重下"
        }
    }

    /// 默认只选日志和开发缓存；废纸篓含用户文件，应用缓存可能仍在使用，均需主动勾选。
    var defaultOn: Bool { self == .userLogs || self == .devCaches }
}

/// 扫描保留文件身份，清理前核对，避免删除扫描之后被替换的同名文件。
struct CleanupIdentity: Sendable, Equatable {
    let device: Int32
    let inode: UInt64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
}

struct CleanupItem: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let bytes: Int64
    var identity: CleanupIdentity? = nil
}

struct CleanupIssue: Identifiable, Sendable {
    var id: String { path + message }
    let path: String
    let message: String
    var permissionDenied = false
}

struct CleanupScanResult: Identifiable, Sendable {
    let category: CleanupCategory
    var id: String { category.rawValue }
    let totalBytes: Int64
    let items: [CleanupItem]
    var issues: [CleanupIssue] = []
    var sizeLabel: String {
        if items.isEmpty && !issues.isEmpty { return "未能读取" }
        return ByteFormat.memory(UInt64(max(0, totalBytes))) + (issues.isEmpty ? "" : " · 部分")
    }
}

struct CleanupReport: Sendable {
    /// 删除项在操作前的磁盘占用估计；APFS 快照等可能使实际可用空间变化不同。
    var freedBytes: Int64 = 0
    var deletedCount: Int = 0
    var failedCount: Int = 0
    var missingCount: Int = 0
    var issues: [CleanupIssue] = []
    var summary: String {
        "已删除 \(deletedCount) 项（约 \(ByteFormat.memory(UInt64(max(0, freedBytes)))))" +
        (failedCount > 0 ? "，失败 \(failedCount) 项" : "") +
        (missingCount > 0 ? "，\(missingCount) 项已不存在" : "")
    }
}

// MARK: - 应用发布信息

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// 发布通道。公开测试期间为 "Beta"，转正式版时改成空字符串即可，
    /// 不要去动 CFBundleShortVersionString——那里必须保持纯 X.Y.Z，
    /// 否则 release.sh 的版本号校验和 Sparkle 的版本比较都会出问题。
    static let channel = "Beta"

    static var displayVersion: String {
        channel.isEmpty ? "\(version) (\(build))" : "\(version) (\(build)) \(channel)"
    }

    static var homepage: URL {
        bundleURL("MacPulseHomepageURL") ?? URL(string: "https://tokenmini.cc")!
    }

    static var privacy: URL {
        bundleURL("MacPulsePrivacyURL") ?? URL(string: "https://tokenmini.cc/privacy")!
    }

    static var source: URL {
        bundleURL("MacPulseSourceURL") ?? URL(string: "https://github.com/ai798-Lab/TokenMini")!
    }

    static var releases: URL { source.appendingPathComponent("releases") }
    static var rankings: URL { homepage.appendingPathComponent("rankings") }

    private static func bundleURL(_ key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}
