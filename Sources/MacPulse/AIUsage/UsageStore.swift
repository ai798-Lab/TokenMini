import Foundation
import Combine
import Darwin

/// AI 用量中心:定时扫描本地会话 JSONL,聚合后发布给 UI。
/// 契约:扫描与计价由独立文件实现 ——
///   UsageScanner:  `final class`,`func scanAll() -> [UsageEvent]`
///                  负责发现 ~/.claude/projects/**/*.jsonl(及 Codex 会话),
///                  解析、按 messageId+requestId 去重、按文件 mtime/offset 增量缓存。
///   PricingTable:  `enum`,`static func pricing(for model: String) -> ModelPricing?`
///                  内置价格表 + 归一化后的精确匹配。
@MainActor
final class UsageStore: ObservableObject {
    // 弹窗/菜单栏"今日一瞥"字段,恒为今日/本月/7天,与 filter 解耦
    @Published var today = UsagePeriodSummary()
    @Published var thisMonth = UsagePeriodSummary()
    @Published var last7Days: [DailyUsage] = []
    @Published var burnRatePerHourUSD: Double = 0     // 最近 1 小时实际花费
    @Published var monthProjectionUSD: Double = 0     // 按本月日均外推整月
    @Published var lastScan: Date?
    @Published var scanning = false
    @Published private(set) var isReaggregating = false
    @Published private(set) var sourceStatuses: [ToolSourceStatus] = []
    @Published private(set) var recentActivity: RecentAIActivity?

    // 监控台窗口:多维筛选 + 即时重聚合
    @Published var filter = UsageFilter() {
        didSet { if oldValue != filter { reaggregate() } }
    }
    @Published private(set) var dashboard = DashboardData()

    /// 供预览/离屏渲染注入现成数据(不触发扫描)
    func injectForPreview(_ d: DashboardData) { dashboard = d }

    /// 最近有活动的工具("当前在用",3 小时内才算),用于额度主角/C 位选择;
    /// 没有近期活动返回 nil,由调用方退回"用得最多"的工具。
    var activeTool: ToolKind? {
        guard let recentActivity,
              recentActivity.timestamp > Date().addingTimeInterval(-3 * 3600) else { return nil }
        return recentActivity.tool
    }

    static let refreshInterval: TimeInterval = 60

    private let catalogStore: ModelCatalogStore
    private let scanOverride: (@Sendable () -> [UsageEvent])?
    init(catalogStore: ModelCatalogStore? = nil, scanOverride: (@Sendable () -> [UsageEvent])? = nil) {
        self.catalogStore = catalogStore ?? .shared
        self.scanOverride = scanOverride
    }

    private let scanner = UsageScanner()      // Claude Code
    private let additionalScanner = AdditionalUsageScanner()
    private let codexScanner = CodexScanner()  // Codex CLI
    private var timer: Timer?
    private let scanQueue = DispatchQueue(label: "macpulse.aiusage", qos: .utility)
    private var priced: [PricedEvent] = []    // 计价后常驻,重聚合只做加法不重扫
    private var pendingCatalogRefresh = false
    private var pricingRevision = PricingTable.snapshotVersion
    private var reaggGen = 0                   // 去抖代次:只发布最新一次结果

    func start() {
        guard timer == nil else { return }
        catalogStore.onChange = { [weak self] in
            guard let self else { return }
            if self.scanning { self.pendingCatalogRefresh = true } else { self.refresh() }
        }
        catalogStore.start()
        refresh()
        // .common 模式,理由同 SystemMonitor:default 模式在 event-tracking 期间会暂停
        let t = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
    }

    /// 排行榜上传用的上海时区当日总量。只返回汇总值，不暴露模型、项目、路径或会话。
    func rankingDailyAggregate(now: Date = Date()) -> RankingDailyAggregate {
        Self.rankingDailyAggregate(events: priced, now: now, appVersion: AppInfo.displayVersion, pricingVersion: pricingRevision)
    }

    nonisolated static func rankingDailyAggregate(
        events: [PricedEvent],
        now: Date,
        appVersion: String,
        pricingVersion: String = PricingTable.snapshotVersion
    ) -> RankingDailyAggregate {
        var calendar = Calendar(identifier: .gregorian)
        // 不用 ! 强制解包:时区数据库异常时会直接崩;退回 UTC 只影响榜单日界,不影响本地功能。
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600) ?? .gmt
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        var tokens: Int64 = 0
        var costUSD = 0.0
        for event in events where event.timestamp >= start && event.timestamp < end {
            tokens += Int64(event.totalTokens)
            costUSD += max(0, event.cost.total)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return RankingDailyAggregate(
            localDay: formatter.string(from: now),
            totalTokens: max(0, tokens),
            estimatedCostMicroUSD: max(0, Int64((costUSD * 1_000_000).rounded())),
            pricingVersion: pricingVersion,
            appVersion: appVersion)
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        let scanOverride = self.scanOverride
        let scanner = self.scanner
        let codexScanner = self.codexScanner
        let additionalScanner = self.additionalScanner
        let filter = self.filter
        let filterGeneration = reaggGen
        PricingTable.reloadCustomPrices()
        let snapshot = PricingSnapshot(catalog: catalogStore.catalog, overrides: PricingTable.customPrices())
        scanQueue.async { [weak self] in
            // 整轮 Foundation 文件遍历/JSON 解码放进一个外层池。只有池先排空，
            // malloc 才能识别并归还扫描时产生的小对象页；仅给逐块解析套池仍会
            // 让 resourceValues/URL/Decoder 的临时对象拖到 GCD block 结束。
            let scanResult = autoreleasepool { () -> (
                priced: [PricedEvent], summary: AggregateResult,
                dashboard: DashboardData, alertDashboard: DashboardData,
                recentActivity: RecentAIActivity?, statuses: [ToolSourceStatus]
            ) in
                // 合并多数据源:Claude Code + Codex CLI(各自内部已防重,来源不重叠可直接拼)
                var events: [UsageEvent]
                var statuses: [ToolSourceStatus] = []
                if let scanOverride {
                    events = scanOverride()
                } else {
                    events = scanner.scanAll()
                    events.append(contentsOf: codexScanner.scanAll())
                    let additional = additionalScanner.scanAll()
                    statuses = [ToolKind.claude, .codex].map { tool in
                        let count = events.filter { $0.sourceApp == tool.rawValue }.count
                        return ToolSourceStatus(tool: tool, count: count, detail: count > 0 ? "本地记录 · 自动更新" : "近 90 天未发现可读取用量")
                    } + additional.statuses
                    events.append(contentsOf: additional.events)
                }
                let now = Date()
                let priced = events.map { PricedEvent.from($0, snapshot: snapshot) }        // 一次计价定型
                let result = Self.aggregate(events: events, now: now, snapshot: snapshot)   // 今日一瞥固定桶
                let dash = UsageAggregator.run(priced, filter: filter, now: now, calendar: .current)
                let alertDash = UsageAggregator.run(
                    priced, filter: UsageFilter(time: .today), now: now, calendar: .current)
                return (priced, result, dash, alertDash, Self.latestActivity(in: priced), statuses)
            }
            malloc_zone_pressure_relief(nil, 0)
            Task { @MainActor in
                guard let self else { return }
                self.priced = scanResult.priced
                self.pricingRevision = snapshot.revision
                self.sourceStatuses = scanResult.statuses
                self.recentActivity = scanResult.recentActivity
                self.today = scanResult.summary.today
                self.thisMonth = scanResult.summary.thisMonth
                self.last7Days = scanResult.summary.last7Days
                self.burnRatePerHourUSD = scanResult.summary.burnRate
                self.monthProjectionUSD = scanResult.summary.projection
                let filterUnchanged = self.reaggGen == filterGeneration
                // Invalidate delayed aggregations that captured the previous priced array.
                self.reaggGen &+= 1
                if filterUnchanged {
                    self.dashboard = scanResult.dashboard
                    self.isReaggregating = false
                } else {
                    // 扫描期间筛选被修改:旧筛选结果不能覆盖新筛选;用刚扫到的数据重算。
                    self.reaggregate()
                }
                self.lastScan = Date()
                self.scanning = false
                if self.pendingCatalogRefresh { self.pendingCatalogRefresh = false; self.refresh() }
                let topProject = scanResult.alertDashboard.insight.topProject.map {
                    DisplaySettings.shared.projectName($0)
                }
                NotificationManager.shared.evaluateCostAlerts(
                    hourlyUSD: scanResult.alertDashboard.burn.perHourUSD,
                    todayUSD: scanResult.alertDashboard.overview.totalCostUSD,
                    topProject: topProject)
            }
        }
    }

    nonisolated static func latestActivity(in events: [PricedEvent]) -> RecentAIActivity? {
        guard let latest = events.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
        return RecentAIActivity(tool: latest.tool, model: latest.model, timestamp: latest.timestamp)
    }

    /// 筛选变更:只重聚合内存事件表,不重扫。60ms 去抖 + 代次丢弃过期结果。
    private func reaggregate() {
        isReaggregating = true
        reaggGen &+= 1
        let gen = reaggGen
        let priced = self.priced
        let filter = self.filter
        scanQueue.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            let dash = UsageAggregator.run(priced, filter: filter, now: Date(), calendar: .current)
            Task { @MainActor in
                guard let self, self.reaggGen == gen else { return }  // 被更晚筛选取代则丢弃
                self.dashboard = dash
                self.isReaggregating = false
            }
        }
    }

    // MARK: - 聚合(纯函数,便于测试)

    struct AggregateResult {
        var today = UsagePeriodSummary()
        var thisMonth = UsagePeriodSummary()
        var last7Days: [DailyUsage] = []
        var burnRate: Double = 0
        var projection: Double = 0
    }

    nonisolated static func aggregate(events: [UsageEvent], now: Date, snapshot: PricingSnapshot? = nil) -> AggregateResult {
        var cal = Calendar.current
        cal.timeZone = .current
        let todayStart = cal.startOfDay(for: now)
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
            return AggregateResult()
        }
        let hourAgo = now.addingTimeInterval(-3600)
        // 7 天窗口下界必须和图表桶同源用日历运算,固定 6×86400 秒在 DST 时区会差 1 小时
        let windowStart = cal.date(byAdding: .day, value: -6, to: todayStart)
            ?? todayStart.addingTimeInterval(-6 * 86400)

        var result = AggregateResult()
        var daily: [String: (cost: Double, tokens: Int)] = [:]
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.timeZone = .current

        for e in events {
            let rate = snapshot.map { $0.pricing(for: e.model, at: e.timestamp) } ?? PricingTable.pricing(for: e.model)
            var cost = e.costUSD ?? rate?.cost(
                input: e.inputTokens, output: e.outputTokens,
                cacheWrite: e.cacheCreationTokens, cacheWrite1h: e.cacheCreation1hTokens,
                cacheRead: e.cacheReadTokens) ?? 0
            // fast 模式按倍率加价;JSONL 自带 costUSD 时已含加价,不重复乘
            if e.costUSD == nil, e.speed == "fast" {
                cost *= snapshot?.fastMultiplier(for: e.model, at: e.timestamp) ?? PricingTable.fastMultiplier(for: e.model)
            }

            if e.timestamp >= todayStart {
                add(&result.today, e, cost)
            }
            if e.timestamp >= monthStart {
                add(&result.thisMonth, e, cost)
            }
            if e.timestamp >= hourAgo {
                result.burnRate += cost
            }
            if e.timestamp >= windowStart {
                let key = dayFmt.string(from: e.timestamp)
                daily[key, default: (0, 0)].cost += cost
                daily[key, default: (0, 0)].tokens += e.inputTokens + e.outputTokens
                    + e.cacheCreationTokens + e.cacheReadTokens
            }
        }

        // 最近 7 天补零,保证图表连续
        result.last7Days = (0..<7).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            let key = dayFmt.string(from: d)
            let v = daily[key] ?? (0, 0)
            return DailyUsage(day: key, costUSD: v.cost, totalTokens: v.tokens)
        }

        // 整月外推:本月日均 × 当月天数
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        if dayOfMonth > 0 {
            result.projection = result.thisMonth.totalCostUSD / Double(dayOfMonth) * Double(daysInMonth)
        }
        return result
    }

    private nonisolated static func add(_ s: inout UsagePeriodSummary, _ e: UsageEvent, _ cost: Double) {
        s.totalCostUSD += cost
        s.inputTokens += e.inputTokens
        s.outputTokens += e.outputTokens
        s.cacheCreationTokens += e.cacheCreationTokens
        s.cacheReadTokens += e.cacheReadTokens
        s.eventCount += 1
        var m = s.byModel[e.model] ?? ModelUsage()
        m.costUSD += cost
        m.inputTokens += e.inputTokens
        m.outputTokens += e.outputTokens
        m.cacheCreationTokens += e.cacheCreationTokens
        m.cacheReadTokens += e.cacheReadTokens
        m.eventCount += 1
        s.byModel[e.model] = m
    }
}
