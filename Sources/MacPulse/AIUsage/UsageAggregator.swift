import Foundation

/// 纯函数聚合器:输入已计价事件 + 筛选条件,单遍算出仪表盘所有分区。
/// nonisolated 无副作用,便于独立测试。
enum UsageAggregator {

    static func run(_ events: [PricedEvent], filter: UsageFilter,
                    now: Date, calendar cal: Calendar, topN: Int = 8) -> DashboardData {
        var data = DashboardData()
        let (start, end) = timeBounds(filter.time, now: now, cal: cal)
        let (prevStart, prevEnd) = comparisonBounds(filter.time, start: start, end: end, cal: cal)
        let types = filter.tokenTypes
        let hourAgo = now.addingTimeInterval(-3600)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))
            ?? cal.startOfDay(for: now)

        // 趋势桶规划
        let plan = BucketPlan(start: start, end: end, cal: cal)
        var trend = plan.emptyPoints()

        var overview = OverviewMetrics()
        var byModel: [String: UsageSlice] = [:]
        var byProject: [String: UsageSlice] = [:]
        var byTool: [ToolKind: UsageSlice] = [:]
        var sessions: [String: SessionSlice] = [:]
        var cacheWriteTok = 0, cacheReadTok = 0, cacheSaved = 0.0
        var prevCost = 0.0
        var burnCost = 0.0
        var monthCost = 0.0
        var unknownModels = Set<String>()
        // facets:时间窗内出现过的项目/模型/工具(不受维度筛选约束)
        var facetTools = Set<ToolKind>(), facetProjects = Set<String>(), facetModels = Set<String>()

        func selTokens(_ e: PricedEvent) -> (input: Int, output: Int, cw: Int, cr: Int) {
            func g(_ t: TokenType, _ v: Int) -> Int { (types.isEmpty || types.contains(t)) ? v : 0 }
            return (g(.input, e.input), g(.output, e.output), g(.cacheWrite, e.cacheWrite), g(.cacheRead, e.cacheRead))
        }

        for e in events {
            let inWindow = e.timestamp >= start && e.timestamp < end
            if inWindow {
                facetTools.insert(e.tool); facetProjects.insert(e.project); facetModels.insert(e.model)
                if !e.isPriced && filter.matchesDimensions(e) { unknownModels.insert(e.model) }
            }
            guard filter.matchesDimensions(e) else {
                // 维度不匹配:仅可能贡献 facet(已在上面收集),跳过计量
                continue
            }
            let selCost = e.cost.selected(types)

            // “过去 1 小时”是固定实时窗口，只受维度/Token 筛选影响，不随顶部时间范围改变。
            if e.timestamp >= hourAgo && e.timestamp <= now { burnCost += selCost }

            // 月度投影只受项目/模型/工具/token 类型筛选影响,不应随仪表盘时间范围跳变。
            if e.timestamp >= monthStart && e.timestamp <= now { monthCost += selCost }

            if inWindow {
                let t = selTokens(e)
                overview.totalCostUSD += selCost
                overview.input += t.input; overview.output += t.output
                overview.cacheWrite += t.cw; overview.cacheRead += t.cr
                overview.eventCount += 1

                accumulate(&byModel, key: e.model, e: e, cost: selCost, types: types)
                accumulate(&byProject, key: e.project, e: e, cost: selCost, types: types)
                accumulateTool(&byTool, key: e.tool, e: e, cost: selCost, types: types)

                cacheWriteTok += t.cw; cacheReadTok += t.cr
                if types.isEmpty || types.contains(.cacheRead) { cacheSaved += e.cacheSavedUSD }

                if let bi = plan.bucketIndex(for: e.timestamp), bi >= 0, bi < trend.count {
                    trend[bi].costUSD += selCost
                    trend[bi].byModel[e.model, default: 0] += selCost
                    trend[bi].byType += filteredBreakdown(e.cost, types)
                }

                var s = sessions[e.session] ?? SessionSlice(session: e.session, project: e.project,
                                                            lastActive: e.timestamp, modelHint: e.model)
                s.costUSD += selCost
                s.tokens += e.tokens(types)
                if e.timestamp > s.lastActive { s.lastActive = e.timestamp; s.modelHint = e.model }
                sessions[e.session] = s

            } else if e.timestamp >= prevStart && e.timestamp < prevEnd {
                prevCost += selCost
            }
        }

        overview.prevCostUSD = prevCost
        data.overview = overview
        data.trend = trend
        data.byModel = finalize(byModel, total: overview.totalCostUSD)
        data.byProject = finalize(byProject, total: overview.totalCostUSD)
        data.byTool = finalize(Dictionary(uniqueKeysWithValues: byTool.map { ($0.key.label, $0.value) }),
                               total: overview.totalCostUSD)
        data.cache = CacheMetrics(hitRate: overview.cacheHitRate, savedUSD: cacheSaved,
                                  writeTokens: cacheWriteTok, readTokens: cacheReadTok)
        data.burn = burnMetrics(monthCost: monthCost, burnCost: burnCost, now: now, cal: cal)
        data.block = currentBlock(events, filter: filter, now: now, cal: cal, types: types)
        data.topSessions = sessions.values.sorted { $0.costUSD > $1.costUSD }.prefix(topN).map { $0 }
        data.facets = Facets(
            tools: facetTools.sorted { $0.rawValue < $1.rawValue },
            projects: facetProjects.sorted(),
            models: facetModels.sorted())
        let topModel = data.byModel.first
        let topProject = data.byProject.first
        let peak = trend.max { $0.costUSD < $1.costUSD }
        data.insight = UsageInsightMetrics(
            deltaUSD: overview.deltaUSD,
            deltaPct: overview.deltaPct,
            topModel: topModel?.key,
            topModelShare: topModel?.share ?? 0,
            topProject: topProject?.key,
            topProjectShare: topProject?.share ?? 0,
            peakLabel: (peak?.costUSD ?? 0) > 0 ? peak?.label : nil,
            peakCostUSD: peak?.costUSD ?? 0)
        data.quality = DataQualityMetrics(
            sources: data.facets.tools,
            unknownModels: unknownModels.sorted())
        return data
    }

    // MARK: - 时间范围

    static func timeBounds(_ range: UsageFilter.TimeRange, now: Date, cal: Calendar) -> (Date, Date) {
        switch range {
        case .last24h:
            return (now.addingTimeInterval(-24 * 3600), now)
        case .today:
            return (cal.startOfDay(for: now), now)
        case .last7Days:
            let s = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
            return (s, now)
        case .last30Days:
            let s = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now)) ?? now
            return (s, now)
        case let .custom(a, b):
            return (min(a, b), max(a, b))
        }
    }

    /// 环比窗口与 UI 文案严格对齐。自然日范围按日历平移，避免“今日”误比昨日后半天。
    static func comparisonBounds(_ range: UsageFilter.TimeRange, start: Date, end: Date,
                                 cal: Calendar) -> (Date, Date) {
        switch range {
        case .last24h:
            return (start.addingTimeInterval(-24 * 3600), start)
        case .today:
            return (cal.date(byAdding: .day, value: -1, to: start) ?? start.addingTimeInterval(-86400),
                    cal.date(byAdding: .day, value: -1, to: end) ?? end.addingTimeInterval(-86400))
        case .last7Days:
            return (cal.date(byAdding: .day, value: -7, to: start) ?? start.addingTimeInterval(-7 * 86400),
                    cal.date(byAdding: .day, value: -7, to: end) ?? end.addingTimeInterval(-7 * 86400))
        case .last30Days:
            return (cal.date(byAdding: .day, value: -30, to: start) ?? start.addingTimeInterval(-30 * 86400),
                    cal.date(byAdding: .day, value: -30, to: end) ?? end.addingTimeInterval(-30 * 86400))
        case .custom:
            let span = end.timeIntervalSince(start)
            return (start.addingTimeInterval(-span), start)
        }
    }

    // MARK: - 累加助手

    private static func filteredBreakdown(_ cb: CostBreakdown, _ types: Set<TokenType>) -> CostBreakdown {
        guard !types.isEmpty else { return cb }
        return CostBreakdown(
            input: types.contains(.input) ? cb.input : 0,
            output: types.contains(.output) ? cb.output : 0,
            cacheWrite: types.contains(.cacheWrite) ? cb.cacheWrite : 0,
            cacheRead: types.contains(.cacheRead) ? cb.cacheRead : 0)
    }

    private static func accumulate(_ dict: inout [String: UsageSlice], key: String,
                                   e: PricedEvent, cost: Double, types: Set<TokenType>) {
        var s = dict[key] ?? UsageSlice(key: key)
        s.costUSD += cost
        s.tokens += e.tokens(types)
        s.breakdown += filteredBreakdown(e.cost, types)
        s.eventCount += 1
        dict[key] = s
    }

    private static func accumulateTool(_ dict: inout [ToolKind: UsageSlice], key: ToolKind,
                                       e: PricedEvent, cost: Double, types: Set<TokenType>) {
        var s = dict[key] ?? UsageSlice(key: key.label)
        s.costUSD += cost
        s.tokens += e.tokens(types)
        s.breakdown += filteredBreakdown(e.cost, types)
        s.eventCount += 1
        dict[key] = s
    }

    private static func finalize(_ dict: [String: UsageSlice], total: Double) -> [UsageSlice] {
        dict.values.map { s -> UsageSlice in
            var s = s
            s.share = total > 0 ? s.costUSD / total : 0
            return s
        }.sorted { $0.costUSD > $1.costUSD }
    }

    private static func burnMetrics(monthCost: Double, burnCost: Double,
                                    now: Date, cal: Calendar) -> BurnMetrics {
        var b = BurnMetrics()
        b.perHourUSD = burnCost      // 近 1 小时成本
        // 整月外推:本月日均 × 当月天数。
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        if dayOfMonth > 0 {
            b.monthProjectionUSD = monthCost / Double(dayOfMonth) * Double(daysInMonth)
        }
        return b
    }

    // MARK: - 5 小时计费块(取含 now 的活动块)

    private static func currentBlock(_ events: [PricedEvent], filter: UsageFilter,
                                     now: Date, cal: Calendar, types: Set<TokenType>) -> Block5h? {
        let blockLen: TimeInterval = 5 * 3600
        // 只看近 ~10 小时、维度匹配的事件,升序
        let recent = events.filter {
            $0.timestamp >= now.addingTimeInterval(-2 * blockLen) && filter.matchesDimensions($0)
        }.sorted { $0.timestamp < $1.timestamp }
        guard let first = recent.first else { return nil }

        // ccusage 语义:块起点 = 首事件按小时向下取整;gap > 5h 或距块起点 > 5h 起新块
        var blockStart = floorToHour(first.timestamp, cal: cal)
        var lastTs = first.timestamp
        for e in recent.dropFirst() {
            if e.timestamp.timeIntervalSince(blockStart) > blockLen
                || e.timestamp.timeIntervalSince(lastTs) > blockLen {
                blockStart = floorToHour(e.timestamp, cal: cal)
            }
            lastTs = e.timestamp
        }
        let blockEnd = blockStart.addingTimeInterval(blockLen)
        // 活动块判定:最后活动距今 < 5h 且 now < 块结束
        guard now.timeIntervalSince(lastTs) < blockLen, now < blockEnd else { return nil }

        var block = Block5h(start: blockStart, end: blockEnd)
        var spent = 0.0
        for e in recent where e.timestamp >= blockStart {
            spent += e.cost.selected(types)
        }
        block.spentUSD = spent
        let elapsedH = max(now.timeIntervalSince(blockStart) / 3600, 0.001)
        block.projectedUSD = spent / elapsedH * (blockLen / 3600)   // 按块内均速外推整块
        return block
    }

    private static func floorToHour(_ d: Date, cal: Calendar) -> Date {
        floorToWholeHour(d, cal: cal)
    }
}

/// 整点向下取整。**不能**用 `Calendar.date(bySetting: .minute, value: 0, of:)`——
/// 它是向前搜索下一个匹配时刻(14:37 → 15:00),会把 24 小时趋势的首桶起点推迟最多 59 分钟,
/// 落在其间的事件计入总额却进不了任何柱子;5 小时计费块的起点也会被推到未来。
private func floorToWholeHour(_ d: Date, cal: Calendar) -> Date {
    cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: d)) ?? d
}

// MARK: - 趋势桶规划

private struct BucketPlan {
    enum Unit { case hour, day, week }
    let unit: Unit
    let start: Date
    let count: Int
    let cal: Calendar
    private let labelFmt: DateFormatter

    init(start: Date, end: Date, cal: Calendar) {
        self.cal = cal
        let span = end.timeIntervalSince(start)
        let fmt = DateFormatter(); fmt.timeZone = cal.timeZone; fmt.locale = Locale(identifier: "en_US_POSIX")
        if span <= 2 * 86400 + 1 {
            unit = .hour
            self.start = floorToWholeHour(start, cal: cal)
            count = max(1, Int(ceil(end.timeIntervalSince(self.start) / 3600)))
            // 标签是分类轴的 domain 与"峰值出现在 …"文案,同一规划内**必须唯一**:
            // 小时桶跨日(24 小时窗从昨天 16:00 排到今天 16:00)要带日期,否则 "16:00" 会出现两次,
            // 两个不同小时的柱子会叠到同一根上。
            fmt.dateFormat = cal.isDate(self.start, inSameDayAs: end) ? "HH:00" : "MM-dd HH:00"
        } else if span <= 92 * 86400 {
            unit = .day
            self.start = cal.startOfDay(for: start)
            count = max(1, (cal.dateComponents([.day], from: self.start, to: cal.startOfDay(for: end)).day ?? 0) + 1)
            fmt.dateFormat = "MM-dd"
        } else {
            unit = .week
            self.start = cal.startOfDay(for: start)
            count = max(1, (cal.dateComponents([.weekOfYear], from: self.start, to: end).weekOfYear ?? 0) + 1)
            fmt.dateFormat = "MM-dd"
        }
        labelFmt = fmt
    }

    func bucketIndex(for date: Date) -> Int? {
        switch unit {
        case .hour: return Int(floor(date.timeIntervalSince(start) / 3600))
        case .day: return cal.dateComponents([.day], from: start, to: cal.startOfDay(for: date)).day
        case .week: return cal.dateComponents([.weekOfYear], from: start, to: date).weekOfYear
        }
    }

    func emptyPoints() -> [TrendPoint] {
        (0..<count).map { i in
            let d: Date
            switch unit {
            case .hour: d = start.addingTimeInterval(Double(i) * 3600)
            case .day: d = cal.date(byAdding: .day, value: i, to: start) ?? start
            case .week: d = cal.date(byAdding: .weekOfYear, value: i, to: start) ?? start
            }
            return TrendPoint(id: i, label: labelFmt.string(from: d), date: d)
        }
    }
}
