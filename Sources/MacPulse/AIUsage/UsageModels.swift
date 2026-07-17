import Foundation

// MARK: - 基础枚举

/// 项目名显示:Claude 的项目是编码目录名(-Users-x-Documents-Foo),解成可读短名;
/// Codex 已是 basename,原样返回。
enum ProjectName {
    static func display(_ raw: String, privacy: Bool = false) -> String {
        if privacy { return privateDisplay(raw) }
        guard raw.hasPrefix("-Users-") else { return raw }
        var tail = raw.split(separator: "-", omittingEmptySubsequences: false)
            .dropFirst(3).filter { !$0.isEmpty }.map(String.init)   // 去 -Users-<user>-
        while let f = tail.first,
              ["Documents", "Desktop", "Downloads", "Movies", "Music", "Pictures"].contains(f) {
            tail.removeFirst()
        }
        return tail.isEmpty ? raw : tail.joined(separator: "/")
    }

    /// 录屏/截图用的稳定匿名名。同一路径跨刷新保持一致,又不泄露真实项目名。
    static func privateDisplay(_ raw: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "项目 %04X", hash & 0xFFFF)
    }
}

enum ToolKind: String, Sendable, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var label: String { self == .claude ? "Claude Code" : "Codex CLI" }
    init?(sourceApp: String) {
        switch sourceApp { case "claude": self = .claude; case "codex": self = .codex; default: return nil }
    }
}

enum TokenType: String, Sendable, CaseIterable, Identifiable {
    case input, output, cacheWrite, cacheRead
    var id: String { rawValue }
    var label: String {
        switch self {
        case .input: return "输入"
        case .output: return "输出"
        case .cacheWrite: return "缓存写"
        case .cacheRead: return "缓存读"
        }
    }
}

/// 四分量成本(美元)
struct CostBreakdown: Sendable, Equatable {
    var input: Double = 0
    var output: Double = 0
    var cacheWrite: Double = 0
    var cacheRead: Double = 0
    var total: Double { input + output + cacheWrite + cacheRead }

    /// 只取选中 token 类型的成本(空集=全算)
    func selected(_ types: Set<TokenType>) -> Double {
        guard !types.isEmpty else { return total }
        var s = 0.0
        if types.contains(.input) { s += input }
        if types.contains(.output) { s += output }
        if types.contains(.cacheWrite) { s += cacheWrite }
        if types.contains(.cacheRead) { s += cacheRead }
        return s
    }

    static func += (lhs: inout CostBreakdown, rhs: CostBreakdown) {
        lhs.input += rhs.input; lhs.output += rhs.output
        lhs.cacheWrite += rhs.cacheWrite; lhs.cacheRead += rhs.cacheRead
    }
}

// MARK: - 常驻内存的已计价事件

/// 扫描出的 UsageEvent 一次性计价后定型;之后按任意筛选重聚合只做加法,不再查价。
struct PricedEvent: Sendable {
    let timestamp: Date
    let tool: ToolKind
    let model: String
    let project: String
    let session: String
    let input: Int
    let output: Int
    let cacheWrite: Int
    let cacheRead: Int
    let cost: CostBreakdown
    let cacheSavedUSD: Double

    var totalTokens: Int { input + output + cacheWrite + cacheRead }

    /// 只取选中 token 类型的 token 数(空集=全算)
    func tokens(_ types: Set<TokenType>) -> Int {
        guard !types.isEmpty else { return totalTokens }
        var n = 0
        if types.contains(.input) { n += input }
        if types.contains(.output) { n += output }
        if types.contains(.cacheWrite) { n += cacheWrite }
        if types.contains(.cacheRead) { n += cacheRead }
        return n
    }

    /// 从原始 UsageEvent 计价成 PricedEvent。JSONL 自带 costUSD 时整体缩放四分量使之和 = 权威值。
    static func from(_ e: UsageEvent) -> PricedEvent {
        let pricing = PricingTable.pricing(for: e.model)
        var cb = pricing?.breakdown(
            input: e.inputTokens, output: e.outputTokens,
            cacheWrite: e.cacheCreationTokens, cacheWrite1h: e.cacheCreation1hTokens,
            cacheRead: e.cacheReadTokens) ?? CostBreakdown()
        // fast 模式倍率(仅在按 token 估价时;自带 costUSD 走缩放分支)
        if e.costUSD == nil, e.speed == "fast" {
            let m = PricingTable.fastMultiplier(for: e.model)
            cb = CostBreakdown(input: cb.input * m, output: cb.output * m,
                               cacheWrite: cb.cacheWrite * m, cacheRead: cb.cacheRead * m)
        }
        // JSONL 自带费用:缩放四分量使总额精确(拆分保持比例)
        if let authoritative = e.costUSD {
            let est = cb.total
            if est > 0 {
                let k = authoritative / est
                cb = CostBreakdown(input: cb.input * k, output: cb.output * k,
                                   cacheWrite: cb.cacheWrite * k, cacheRead: cb.cacheRead * k)
            } else {
                cb = CostBreakdown(input: authoritative, output: 0, cacheWrite: 0, cacheRead: 0)
            }
        }
        return PricedEvent(
            timestamp: e.timestamp,
            tool: ToolKind(sourceApp: e.sourceApp) ?? .claude,
            model: e.model,
            project: e.project,
            session: e.sessionID,
            input: e.inputTokens,
            output: e.outputTokens,
            cacheWrite: e.cacheCreationTokens,
            cacheRead: e.cacheReadTokens,
            cost: cb,
            cacheSavedUSD: pricing?.cacheSaved(cacheRead: e.cacheReadTokens) ?? 0)
    }
}

// MARK: - 筛选条件

struct UsageFilter: Equatable, Sendable {
    enum TimeRange: Equatable, Sendable, Hashable {
        case last24h, today, last7Days, last30Days
        case custom(Date, Date)

        var label: String {
            switch self {
            case .last24h: return "24 小时"
            case .today: return "今日"
            case .last7Days: return "7 天"
            case .last30Days: return "30 天"
            case .custom: return "自定义"
            }
        }

        /// 环比必须明确基准,否则裸百分比会被误读。
        var comparisonLabel: String {
            switch self {
            case .last24h: return "较前 24 小时"
            case .today: return "较昨日同期"
            case .last7Days: return "较前 7 天"
            case .last30Days: return "较前 30 天"
            case .custom: return "较前一同长周期"
            }
        }
    }
    var time: TimeRange = .today
    var tools: Set<ToolKind> = []        // 空 = 全部
    var projects: Set<String> = []
    var models: Set<String> = []
    var tokenTypes: Set<TokenType> = []  // 空 = 四类全算
    var session: String? = nil           // 下钻单会话

    /// 事件是否命中各维度(时间除外,由聚合器另判)
    func matchesDimensions(_ e: PricedEvent) -> Bool {
        if !tools.isEmpty && !tools.contains(e.tool) { return false }
        if !projects.isEmpty && !projects.contains(e.project) { return false }
        if !models.isEmpty && !models.contains(e.model) { return false }
        if let s = session, e.session != s { return false }
        return true
    }
}

// MARK: - 仪表盘输出数据

struct OverviewMetrics: Sendable {
    var totalCostUSD: Double = 0
    var prevCostUSD: Double = 0          // 上一同长周期,用于环比
    var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    var eventCount = 0

    var totalTokens: Int { input + output + cacheWrite + cacheRead }
    /// 真正新增处理量:输入、输出和缓存写。缓存读是复用,单列避免“总量与明细对不上”。
    var newTokens: Int { input + output + cacheWrite }
    var reusedTokens: Int { cacheRead }
    var deltaUSD: Double { totalCostUSD - prevCostUSD }
    var deltaPct: Double? { prevCostUSD > 0 ? (totalCostUSD - prevCostUSD) / prevCostUSD : nil }
    /// 缓存命中率 = 缓存读 /(输入 + 缓存写 + 缓存读)
    var cacheHitRate: Double {
        let denom = Double(input + cacheWrite + cacheRead)
        return denom > 0 ? Double(cacheRead) / denom : 0
    }
}

struct TrendPoint: Identifiable, Sendable {
    let id: Int
    let label: String
    let date: Date
    var costUSD: Double = 0
    var byModel: [String: Double] = [:]   // 该桶各模型成本(按模型堆叠用)
    var byType = CostBreakdown()          // 该桶四类成本(按 token 类型堆叠用)
}

/// 通用分组切片(模型 / 项目 / 工具)
struct UsageSlice: Identifiable, Sendable {
    let key: String
    var id: String { key }
    var costUSD: Double = 0
    var tokens: Int = 0
    var breakdown = CostBreakdown()
    var eventCount = 0
    var share: Double = 0                 // 占总成本比例,聚合末尾填
}

struct CacheMetrics: Sendable {
    var hitRate: Double = 0
    var savedUSD: Double = 0
    var writeTokens = 0
    var readTokens = 0
    /// 缓存浪费提示:写了很多却很少被读命中(写>0 且 读/写 < 0.5)
    var wasteful: Bool { writeTokens > 0 && Double(readTokens) / Double(writeTokens) < 0.5 }
}

struct BurnMetrics: Sendable {
    var perHourUSD: Double = 0
    var monthProjectionUSD: Double = 0
}

/// 一句话洞察所需的纯数据。文案和隐私别名留给 UI,避免聚合层绑定主题或语言。
struct UsageInsightMetrics: Sendable {
    var deltaUSD: Double = 0
    var deltaPct: Double?
    var topModel: String?
    var topModelShare: Double = 0
    var topProject: String?
    var topProjectShare: Double = 0
    var peakLabel: String?
    var peakCostUSD: Double = 0
}

struct DataQualityMetrics: Sendable {
    var sources: [ToolKind] = []
    var unknownModels: [String] = []
}

/// 当前 5 小时计费块
struct Block5h: Sendable {
    var start: Date
    var end: Date
    var spentUSD: Double = 0
    var projectedUSD: Double = 0          // 按 burn rate 外推整块
    /// 时间进度 0~1
    func progress(now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }
}

struct SessionSlice: Identifiable, Sendable {
    let session: String
    var id: String { session }
    let project: String
    var costUSD: Double = 0
    var tokens: Int = 0
    var lastActive: Date
    var modelHint: String = ""
}

/// 供筛选菜单的可选项(窗口时间范围内出现过的,不受其它维度约束)
struct Facets: Sendable {
    var tools: [ToolKind] = []
    var projects: [String] = []
    var models: [String] = []
}

struct DashboardData: Sendable {
    var overview = OverviewMetrics()
    var trend: [TrendPoint] = []
    var byModel: [UsageSlice] = []
    var byProject: [UsageSlice] = []
    var byTool: [UsageSlice] = []
    var cache = CacheMetrics()
    var burn = BurnMetrics()
    var block: Block5h?
    var topSessions: [SessionSlice] = []
    var facets = Facets()
    var insight = UsageInsightMetrics()
    var quality = DataQualityMetrics()
}
