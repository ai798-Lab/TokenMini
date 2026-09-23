import SwiftUI
import Charts
import AppKit

/// Token 监控台窗口根:顶部筛选栏 + 可滚动内容(概览 / 趋势 / 模型 / 项目·工具)。
struct DashboardRoot: View {
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var quota: QuotaStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        VStack(spacing: 0) {
            FilterBar()
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background(filterBarBackground)
            themeDivider
            Group {
                // 深色皮肤(HUD/LED)一律自绘滚动条,只是发光色不同
                if settings.isDarkSkin {
                    HUDScrollView(accent: settings.isLED ? LED.amber : HUD.cyan) { scrollContent }
                } else {
                    ScrollView { scrollContent }
                }
            }
            .background(scrollBackground)
        }
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .background(settings.isLED ? LED.bg : (settings.isHUD ? HUD.bg : Color.clear))
        .tint(themeTint)
        .preferredColorScheme(settings.isDarkSkin ? .dark : nil)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .onAppear { bringToFront() }
        .onDisappear {
            // 监控台关闭 → 回纯菜单栏态(隐藏 Dock 图标)
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// 强调色:LED 琥珀 / HUD 青 / 经典跟随系统
    private var themeTint: Color? {
        if settings.isLED { return LED.amber }
        if settings.isHUD { return HUD.cyan }
        return nil
    }

    @ViewBuilder
    private var filterBarBackground: some View {
        if settings.isPrism { Rectangle().fill(Prism.bg) }
        else if settings.isLED { Rectangle().fill(LED.bg.opacity(0.96)) }
        else if settings.isHUD { Rectangle().fill(HUD.bg.opacity(0.96)) }
        else { Rectangle().fill(.bar) }
    }

    /// 分隔线:深色皮肤都是"暗轨 + 一小段发光",发光色按主题走
    @ViewBuilder
    private var themeDivider: some View {
        if settings.isPrism {
            Rectangle().fill(Prism.mint.opacity(0.65))
                .frame(maxWidth: .infinity).frame(height: 1)
        } else if settings.isDarkSkin {
            let accent = settings.isLED ? LED.amber : HUD.cyan
            ZStack(alignment: .leading) {
                Rectangle().fill(settings.isLED ? LED.amber.opacity(0.12) : HUD.gridline).frame(height: 1)
                Rectangle().fill(accent.opacity(0.8)).frame(width: 90, height: 1)
                    .shadow(color: accent.opacity(0.6), radius: 2)
            }
        } else {
            Divider()
        }
    }

    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if settings.isPrism { prismHero }
            dashboardCards.padding(20)
        }
        .frame(maxWidth: .infinity)
    }

    private var prismHero: some View {
        let overview = usage.dashboard.overview
        let ready = usage.lastScan != nil
        let tools = usage.filter.tools.isEmpty ? "全部工具" : usage.filter.tools.map(\.label).sorted().joined(separator: "、")
        return PrismDashboardBanner(
            total: ready ? settings.tokens(overview.totalTokens) : "—",
            scope: "\(usage.filter.time.label) · \(tools)",
            calls: ready ? "\(overview.eventCount.formatted()) 次调用" : "正在读取本地用量…",
            input: ready ? settings.tokens(overview.input) : "—",
            output: ready ? settings.tokens(overview.output) : "—",
            cacheWrite: ready ? settings.tokens(overview.cacheWrite) : "—",
            cacheRead: ready ? settings.tokens(overview.cacheRead) : "—")
    }

    private var dashboardCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            DataStatusBar()
            OverviewCards()
            InsightCard()
            if settings.dashboardMode == .analysis {
                TokenCompositionCard()
            }
            TrendCard()
            if settings.dashboardMode == .analysis {
                HStack(alignment: .top, spacing: 16) {
                    ModelBreakdownCard()
                    GroupRankingCard()
                }
            }
        }
    }

    /// 把监控台窗口强制置顶。菜单栏 app(.accessory)开独立窗口时,单靠 openWindow
    /// 常常开在活跃 app 后面;需切 .regular + 找到 NSWindow 显式 makeKeyAndOrderFront。
    private func bringToFront() {
        NSApp.setActivationPolicy(.regular)
        // 下一 runloop 窗口已建好再置顶
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let win = NSApp.windows.first { $0.identifier?.rawValue == "dashboard" || $0.title == "Token 监控台" }
            (win ?? NSApp.windows.last { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            win?.orderFrontRegardless()
        }
    }

    /// 内容区背景:LED = 近黑底 + 极淡点阵;HUD = 深空底 + 极淡工程网格;经典 = 原版窗口色渐变
    @ViewBuilder
    private var scrollBackground: some View {
        if settings.isLED {
            ZStack {
                LED.bg
                LEDDotMatrix(tint: LED.amber, pitch: 6, alpha: 0.05)
            }
            .ignoresSafeArea()
        } else if settings.isHUD {
            ZStack {
                HUD.bg
                if !settings.isPrism { HUDGridBackground() }
            }
            .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor),
                         Color(nsColor: .windowBackgroundColor).opacity(0.6)],
                startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        }
    }
}

// MARK: - 筛选栏

private struct FilterBar: View {
    @State private var showSources = false
    @EnvironmentObject var usage: UsageStore
    @Environment(\.openWindow) private var openWindow
    private let presets: [UsageFilter.TimeRange] = [.last24h, .today, .last7Days, .last30Days]

    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    timePresets
                    Spacer(minLength: 16)
                    dashboardActions
                }
                VStack(alignment: .trailing, spacing: 8) {
                    HStack { timePresets; Spacer() }
                    dashboardActions
                }
            }
            HStack(spacing: 10) {
                multiMenu("工具", options: usage.dashboard.facets.tools.map { ($0.rawValue, $0.label) },
                          selection: toolBinding)
                multiMenu("项目", options: usage.dashboard.facets.projects.map {
                    ($0, settings.projectName($0))
                }, selection: $usage.filter.projects)
                multiMenu("模型", options: usage.dashboard.facets.models.map { ($0, shortModel($0)) },
                          selection: $usage.filter.models)
                multiMenu("Token 构成", options: TokenType.allCases.map { ($0.rawValue, $0.label) },
                          selection: tokenTypeBinding)
                Spacer()
                if usage.filter != UsageFilter(time: usage.filter.time) {
                    Button("重置筛选") { usage.filter = UsageFilter(time: usage.filter.time) }
                        .buttonStyle(ThemedToolbarButtonStyle())
                        .font(settings.isLED ? LED.display(10, .medium)
                              : (settings.isHUD ? HUD.mono(10) : .caption))
                        .foregroundStyle(settings.isLED ? LED.dim
                                         : (settings.isHUD ? HUD.dim : Color.secondary))
                }
            }
            if usage.filter != UsageFilter(time: usage.filter.time) { selectedFilters }
            if usage.isReaggregating {
                HStack { ProgressView().controlSize(.mini); Text("正在按所选条件计算…").font(.caption); Spacer() }
            }
        }
    }

    private var timePresets: some View {
        ThemedSegmented(items: presets.map { ($0, $0.label) }, selection: $usage.filter.time)
    }

    private var dashboardActions: some View {
        HStack(spacing: 8) {
            ForEach(DashboardMode.allCases) { mode in
                let selected = settings.dashboardMode == mode
                Button { settings.dashboardMode = mode } label: {
                    DashboardToolbarLabel(title: mode.label,
                                          icon: mode == .overview ? "square.grid.2x2" : "chart.xyaxis.line",
                                          selected: selected)
                }
                .buttonStyle(DashboardToolbarButtonStyle(selected: selected))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Button { openWindow(id: "leaderboard") } label: {
                DashboardToolbarLabel(title: "排行", icon: "trophy")
            }
            .buttonStyle(DashboardToolbarButtonStyle())
            .help("社区排行榜")
            Button { showSources = true } label: {
                DashboardToolbarLabel(title: "数据源", icon: "externaldrive")
            }
            .buttonStyle(DashboardToolbarButtonStyle())
            .help("工具与模型接入")
            .sheet(isPresented: $showSources) { UsageSourcesView().environmentObject(usage) }
            DisplaySettingsMenu(unifiedToolbar: true)
        }
        .fixedSize()
    }

    // 把 Set<ToolKind>/Set<TokenType> 桥接成 Set<String> 供通用菜单
    private var toolBinding: Binding<Set<String>> {
        Binding(get: { Set(usage.filter.tools.map { $0.rawValue }) },
                set: { usage.filter.tools = Set($0.compactMap { ToolKind(rawValue: $0) }) })
    }
    private var tokenTypeBinding: Binding<Set<String>> {
        Binding(get: { Set(usage.filter.tokenTypes.map { $0.rawValue }) },
                set: { usage.filter.tokenTypes = Set($0.compactMap { TokenType(rawValue: $0) }) })
    }

    private func multiMenu(_ title: String, options: [(key: String, label: String)],
                           selection: Binding<Set<String>>) -> some View {
        MultiSelectFilter(title: title, options: options, selection: selection)
    }

    private var selectedFilters: some View {
        FilterChipsLayout {
            ForEach(usage.filter.tools.sorted { $0.label < $1.label }) { tool in
                chip(tool.label) { usage.filter.tools.remove(tool) }
            }
            ForEach(usage.filter.models.sorted(), id: \.self) { model in
                chip(shortModel(model)) { usage.filter.models.remove(model) }
            }
            ForEach(usage.filter.projects.sorted(), id: \.self) { project in
                chip(settings.projectName(project)) { usage.filter.projects.remove(project) }
            }
            ForEach(usage.filter.tokenTypes.sorted { $0.rawValue < $1.rawValue }) { type in
                chip(type.label) { usage.filter.tokenTypes.remove(type) }
            }
        }
    }

    private func chip(_ label: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) { Text(label).lineLimit(1); Image(systemName: "xmark").font(.system(size: 8)) }
                .font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 5)
                .foregroundStyle(themeAccent()).background(themeAccent().opacity(0.12), in: Capsule())
        }.buttonStyle(.plain).help("取消选择：" + label).accessibilityLabel("取消选择：" + label)
    }

}

// MARK: - 数据状态 / 决策洞察

private struct DataStatusBar: View {
    @EnvironmentObject var usage: UsageStore
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        GlassCard(padding: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    statusLabels
                    Spacer(minLength: 8)
                    disclaimer
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) { statusLabels }
                    disclaimer
                }
            }
            .font(settings.isLED ? LED.mono(9)
                  : (settings.isHUD ? HUD.mono(9) : .caption))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusLabels: some View {
        Label(refreshText, systemImage: usage.scanning ? "arrow.triangle.2.circlepath" : "clock")
        Label(sourceText, systemImage: "externaldrive.connected.to.line.below")
        if !usage.dashboard.quality.unknownModels.isEmpty {
            Label("\(usage.dashboard.quality.unknownModels.count) 个模型待定价（用量已计入）",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(warningColor)
                .help(usage.dashboard.quality.unknownModels.joined(separator: "\n"))
        }
        if settings.privacyMode {
            Label("隐私模式", systemImage: "eye.slash")
                .foregroundStyle(accentColor)
        }
    }

    private var disclaimer: some View {
        Text("API 等价预估，非订阅实际扣款")
            .foregroundStyle(mutedColor)
    }

    private var refreshText: String {
        if usage.scanning { return "正在更新" }
        guard let date = usage.lastScan else { return "等待首次扫描" }
        return "更新于 " + date.formatted(date: .omitted, time: .standard)
    }

    private var sourceText: String {
        let sources = usage.dashboard.quality.sources.map(\.label)
        return sources.isEmpty ? "暂无数据源" : sources.count > 2 ? "已接入 \(sources.count) 个用量来源" : "来源 " + sources.joined(separator: " + ")
    }

    private var mutedColor: Color {
        settings.isLED ? LED.faint : (settings.isHUD ? HUD.faint : .secondary)
    }
    private var accentColor: Color { settings.isLED ? LED.amber : (settings.isHUD ? HUD.cyan : .accentColor) }
    private var warningColor: Color { settings.isLED ? LED.red : (settings.isHUD ? HUD.amber : .orange) }
}

private struct InsightCard: View {
    @EnvironmentObject var usage: UsageStore
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "使用洞察", icon: "sparkles")
                Text(insightText)
                    .font(settings.isLED ? LED.display(13, .medium)
                          : (settings.isHUD ? HUD.mono(12) : .body))
                    .foregroundStyle(settings.isLED ? LED.text
                                     : (settings.isHUD ? HUD.text : Color.primary))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Label("本月外推 \(settings.currencyStr(usage.dashboard.burn.monthProjectionUSD))",
                          systemImage: "calendar")
                        .help("按本月至今日的日均等价成本外推整月，不受顶部时间范围影响")
                    Spacer()
                    if let model = usage.dashboard.insight.topModel {
                        drillButton("聚焦 \(shortModel(model))", icon: "cpu") {
                            toggleModel(model)
                        }
                    }
                    if let project = usage.dashboard.insight.topProject {
                        drillButton("聚焦 \(settings.projectName(project))", icon: "folder") {
                            toggleProject(project)
                        }
                    }
                }
                .font(settings.isLED ? LED.mono(9)
                      : (settings.isHUD ? HUD.mono(9) : .caption))
                .foregroundStyle(settings.isLED ? LED.dim
                                 : (settings.isHUD ? HUD.dim : Color.secondary))
            }
        }
    }

    private var insightText: String {
        let d = usage.dashboard.insight
        var parts: [String] = []
        if let pct = d.deltaPct {
            let direction = d.deltaUSD >= 0 ? "增加" : "减少"
            parts.append("API 等价预估\(usage.filter.time.comparisonLabel)\(direction)"
                         + " \(settings.currencyStr(abs(d.deltaUSD)))（\(String(format: "%.0f", abs(pct) * 100))%）")
        } else {
            parts.append("本时段 API 等价预估为 \(settings.currencyStr(usage.dashboard.overview.totalCostUSD))，暂无可比上一周期")
        }
        if let model = d.topModel {
            parts.append("\(shortModel(model)) 占成本 \(String(format: "%.0f", d.topModelShare * 100))%")
        }
        if let project = d.topProject {
            parts.append("主要项目是 \(settings.projectName(project))（\(String(format: "%.0f", d.topProjectShare * 100))%）")
        }
        if let peak = d.peakLabel {
            parts.append("峰值出现在 \(peak)，为 \(settings.currencyStr(d.peakCostUSD))")
        }
        return parts.joined(separator: "；") + "。"
    }

    @ViewBuilder
    private func drillButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(themeAccent())
        .help("点击切换该筛选，再点一次取消")
    }

    private func toggleModel(_ model: String) {
        usage.filter.models = usage.filter.models == [model] ? [] : [model]
    }
    private func toggleProject(_ project: String) {
        usage.filter.projects = usage.filter.projects == [project] ? [] : [project]
    }
}

private struct TokenCompositionCard: View {
    @EnvironmentObject var usage: UsageStore
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        let o = usage.dashboard.overview
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Token 构成", icon: "square.stack.3d.up")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 8) {
                    item("新增处理量", settings.tokens(o.newTokens), "输入 + 输出 + 缓存写")
                    item("输入", settings.tokens(o.input), nil)
                    item("输出", settings.tokens(o.output), nil)
                    item("缓存写入", settings.tokens(o.cacheWrite), "建立可复用缓存")
                    item("缓存复用", settings.tokens(o.reusedTokens), "不计入新增处理量")
                }
                Text("共 \(o.eventCount) 次调用 · 缓存复用单列，因此不会再与输入/输出合计产生误解")
                    .font(settings.isLED ? LED.mono(9)
                          : (settings.isHUD ? HUD.mono(9) : .caption))
                    .foregroundStyle(settings.isLED ? LED.faint
                                     : (settings.isHUD ? HUD.faint : Color.secondary))
            }
        }
    }

    private func item(_ title: String, _ value: String, _ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(settings.isLED ? LED.display(10, .medium)
                      : (settings.isHUD ? HUD.mono(9) : .caption))
                .foregroundStyle(settings.isLED ? LED.dim
                                 : (settings.isHUD ? HUD.dim : Color.secondary))
            Text(value)
                .font(settings.isLED ? LED.mono(18, .bold)
                      : (settings.isHUD ? HUD.mono(18, .bold)
                         : .system(size: 20, weight: .semibold, design: .rounded)))
                .foregroundStyle(settings.isLED ? LED.amber
                                 : (settings.isHUD ? HUD.text : Color.primary))
                .lineLimit(1).minimumScaleFactor(0.7)
            if let note {
                Text(note)
                    .font(settings.isLED ? LED.mono(8)
                          : (settings.isHUD ? HUD.mono(8) : .caption2))
                    .foregroundStyle(settings.isLED ? LED.faint
                                     : (settings.isHUD ? HUD.faint : Color.secondary))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 概览卡

private struct OverviewCards: View {
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var quota: QuotaStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        let o = usage.dashboard.overview
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
            GlassCard {
                MetricTile(title: "API 等价预估", value: settings.currencyStr(o.totalCostUSD),
                           delta: o.deltaPct,
                           deltaAbsolute: o.deltaPct == nil ? nil : signedCurrency(o.deltaUSD),
                           deltaContext: o.deltaPct == nil ? nil : usage.filter.time.comparisonLabel,
                           subtitle: "筛选范围 · \(o.eventCount) 次调用",
                           code: "API EQUIV.")
            }
            GlassCard {
                quotaTile
            }
            GlassCard {
                MetricTile(title: "当前消耗速度",
                           value: settings.currencyStr(usage.dashboard.burn.perHourUSD) + "/h",
                           subtitle: "过去 1 小时 · 固定实时窗口",
                           code: "BURN RATE")
            }
            GlassCard {
                MetricTile(title: "输入缓存复用率",
                           value: String(format: "%.0f%%", o.cacheHitRate * 100),
                           subtitle: "复用 \(settings.tokens(o.reusedTokens)) · 理论省 \(settings.currencyStr(usage.dashboard.cache.savedUSD))",
                           accent: settings.isLED ? LED.green : HUD.green,
                           code: "CACHE REUSE")
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8),
                   value: o.totalCostUSD)
    }

    private func signedCurrency(_ usd: Double) -> String? {
        guard abs(usd) > 0.000_001 else { return nil }
        return (usd > 0 ? "+" : "−") + settings.currencyStr(abs(usd))
    }

    @ViewBuilder
    private var quotaTile: some View {
        let now = Date()
        if let w = quota.mostConstrained(now: now) {
            let used = w.effectiveUsed(now: now)
            let available = max(0, 100 - used)
            MetricTile(title: "额度状态",
                       value: "\(w.tool.label) \(String(format: "%.0f", available))% 可用",
                       subtitle: w.hasReset(now: now)
                        ? "\(w.kind.shortLabel) · 已重置，等待新快照"
                        : "\(w.kind.shortLabel) · \(QuotaFormat.duration(w.remaining(now: now))) 后重置",
                       accent: quotaColor(used), code: "QUOTA")
        } else {
            MetricTile(title: "额度状态", value: "暂不可用",
                       subtitle: "等待 Claude / Codex 额度数据", code: "QUOTA")
        }
    }

    private func quotaColor(_ used: Double) -> Color {
        if settings.isLED { return used >= 85 ? LED.red : (used >= 65 ? LED.amber : LED.green) }
        if settings.isHUD { return used >= 85 ? HUD.red : (used >= 65 ? HUD.amber : HUD.green) }
        return used >= 85 ? .red : (used >= 65 ? .orange : .green)
    }
}

// MARK: - 趋势

private struct TrendCard: View {
    @EnvironmentObject var usage: UsageStore
    @ObservedObject private var settings = DisplaySettings.shared
    @State private var stackByModel = true
    @State private var plotWidth: CGFloat = 600
    @State private var selectedBucket: String?

    private struct Bar: Identifiable {
        let bucket: String
        let series: String
        let cost: Double
        var id: String { bucket + "|" + series }
    }

    private var hourly: Bool {
        let points = usage.dashboard.trend
        if points.count > 1 { return points[1].date.timeIntervalSince(points[0].date) <= 3600 }
        switch usage.filter.time {
        case .last24h, .today: return true
        case .custom(let start, let end): return end.timeIntervalSince(start) <= 2 * 86400 + 1
        default: return false
        }
    }
    private var axis: TrendAxisLayout { TrendAxisLayout(points: usage.dashboard.trend, hourly: hourly) }
    private var axisColor: Color {
        settings.isPrism ? Prism.secondary : (settings.isLED ? LED.dim : (settings.isHUD ? HUD.dim : .secondary))
    }
    private var gridColor: Color {
        settings.isPrism ? Prism.line.opacity(0.5) : (settings.isLED ? LED.amber.opacity(0.07) : (settings.isHUD ? HUD.gridline : Color.secondary.opacity(0.15)))
    }

    private var bars: [Bar] {
        usage.dashboard.trend.flatMap { point in
            let parts: [(String, Double)] = stackByModel
                ? point.byModel.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
                : [("输入", point.byType.input), ("输出", point.byType.output),
                   ("缓存写", point.byType.cacheWrite), ("缓存读", point.byType.cacheRead)]
            return parts.filter { $0.1 > 0 }.map { Bar(bucket: point.label, series: $0.0, cost: $0.1) }
        }
    }

    /// Retain the full unique category keys. Short display labels must never merge buckets.
    private var xDomain: [String] {
        var seen = Set<String>()
        return usage.dashboard.trend.compactMap { seen.insert($0.label).inserted ? $0.label : nil }
    }
    private var series: [String] {
        var seen = Set<String>()
        return bars.compactMap { seen.insert(shortModel($0.series)).inserted ? shortModel($0.series) : nil }
    }
    private var selectedPoint: TrendPoint? {
        usage.dashboard.trend.first { $0.label == selectedBucket }
    }
    private var intervalText: String {
        let (start, end) = UsageAggregator.timeBounds(usage.filter.time, now: usage.lastScan ?? Date(), cal: .current)
        let pattern = hourly ? "MM/dd HH:mm" : "MM/dd"
        return axis.format(start, pattern) + " — " + axis.format(end, pattern)
            + (hourly ? " · 每小时汇总 · 本地时间" : " · 每天汇总 · 本地时间")
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "等价成本趋势", icon: "chart.bar.xaxis",
                              trailing: AnyView(ThemedSegmented(items: [(true, "按模型"), (false, "成本构成")],
                                                               selection: $stackByModel, size: 9)))
                Text(intervalText)
                    .font(.system(size: 11)).foregroundStyle(axisColor)
                if usage.dashboard.trend.allSatisfy({ $0.costUSD == 0 }) {
                    Text("该范围内无数据").font(.caption).foregroundStyle(axisColor)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    trendChart
                        // Keep the existing crash safeguard: disappearing categories cannot
                        // animate into a new categorical domain when the time filter changes.
                        .transaction { $0.animation = nil }
                    ThemedChartLegend(series: series).padding(.top, 2)
                    selectionDetail
                }
            }
        }
        .onChange(of: xDomain) { _, _ in selectedBucket = nil }
    }

    private var trendChart: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("时间", bar.bucket), y: .value("等价成本", bar.cost),
                        width: .ratio(settings.isLED ? 0.55 : 0.7))
                    .foregroundStyle(SeriesColor.color(for: shortModel(bar.series)))
                    .cornerRadius(settings.isLED ? 2 : 1)
                    .accessibilityLabel(bar.bucket + " · " + shortModel(bar.series))
                    .accessibilityValue(settings.currencyStr(bar.cost))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: xDomain)
        .chartPlotStyle { plot in
            plot.overlay { if settings.isLED { LEDCellMask().allowsHitTesting(false) } }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine().foregroundStyle(gridColor)
                AxisValueLabel {
                    if let cost = value.as(Double.self) {
                        Text(settings.currencyCompact(cost)).font(.system(size: 11)).foregroundStyle(axisColor)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: axis.ticks(plotWidth: Double(plotWidth))) { value in
                AxisValueLabel {
                    if let key = value.as(String.self) {
                        Text(axis.shortLabel(for: key)).font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(axisColor)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    let band = frame.width / CGFloat(max(1, xDomain.count))
                    ZStack(alignment: .topLeading) {
                        ForEach(axis.dateMarkers(plotWidth: frame.width)) { marker in
                            if let center = proxy.position(forX: marker.key) {
                                let x = frame.minX + center - band / 2
                                if marker.index > 0 {
                                    Path { path in
                                        path.move(to: CGPoint(x: x, y: frame.minY))
                                        path.addLine(to: CGPoint(x: x, y: frame.maxY))
                                    }
                                    .stroke(axisColor.opacity(0.35), lineWidth: 1)
                                }
                                Text(marker.text).font(.system(size: 11, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(axisColor)
                                    .frame(width: 56, alignment: .leading)
                                    .position(x: min(max(x, frame.minX), frame.maxX - 56) + 28,
                                              y: frame.maxY + 36)
                            }
                        }
                        if let selectedBucket, let x = proxy.position(forX: selectedBucket) {
                            Path { path in
                                path.move(to: CGPoint(x: frame.minX + x, y: frame.minY))
                                path.addLine(to: CGPoint(x: frame.minX + x, y: frame.maxY))
                            }
                            .stroke(axisColor.opacity(0.6), lineWidth: 1)
                        }
                    }
                    .allowsHitTesting(false)
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .onContinuousHover { phase in
                            if case .active(let location) = phase {
                                selectedBucket = proxy.value(atX: location.x, as: String.self)
                            }
                        }
                        .onTapGesture { location in
                            selectedBucket = proxy.value(atX: location.x, as: String.self)
                        }
                        .accessibilityHidden(true)
                    Color.clear
                        .onAppear { plotWidth = frame.width }
                        .onChange(of: frame.width) { _, width in plotWidth = width }
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 218)
        .padding(.bottom, hourly ? 24 : 0)
    }

    @ViewBuilder private var selectionDetail: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let point = selectedPoint {
                Text(detailDate(point) + " · 等价成本 " + settings.currencyStr(point.costUSD))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                let parts = bars.filter { $0.bucket == point.label }
                    .map { shortModel($0.series) + " " + settings.currencyStr($0.cost) }
                Text(parts.joined(separator: "    "))
                    .font(.system(size: 11)).foregroundStyle(axisColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("移到或点击柱子，查看完整时间与费用明细")
                    .font(.system(size: 11)).foregroundStyle(axisColor)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func detailDate(_ point: TrendPoint) -> String {
        guard hourly else { return axis.format(point.date, "yyyy/MM/dd") }
        let end = point.date.addingTimeInterval(3600)
        return axis.format(point.date, "MM/dd HH:mm") + "–" + axis.format(end, "HH:mm")
    }
}

// MARK: - 空态标签(卡片内共用)

private struct EmptyLabel: View {
    var text = "无数据"
    @ObservedObject private var settings = DisplaySettings.shared
    var body: some View {
        Text(text)
            .font(settings.isLED ? LED.mono(10) : (settings.isHUD ? HUD.mono(10) : .caption))
            .foregroundStyle(settings.isLED ? LED.faint
                             : (settings.isHUD ? HUD.faint : Color.secondary.opacity(0.6)))
    }
}

// MARK: - 模型拆分(甜甜圈 + 明细)

private struct ModelBreakdownCard: View {
    @EnvironmentObject var usage: UsageStore
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        let models = Array(usage.dashboard.byModel.prefix(6))
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "按模型", icon: "cpu")
                if models.isEmpty {
                    EmptyLabel()
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        ZStack {
                            // 深色皮肤下给甜甜圈垫一圈暗轨 + 中心辉光,读起来像仪表而不是通用图表
                            if settings.isDarkSkin {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 20)
                                    .frame(width: 108, height: 108)
                                Circle()
                                    .fill(RadialGradient(
                                        colors: [themeAccent().opacity(0.16), .clear],
                                        center: .center, startRadius: 0, endRadius: 44))
                                    .frame(width: 88, height: 88)
                            }
                            Chart(models) { s in
                                SectorMark(angle: .value("花费", s.costUSD),
                                           innerRadius: .ratio(0.62),
                                           angularInset: settings.isHUD ? 2 : 1.5)
                                    .foregroundStyle(SeriesColor.color(for: s.key))
                                    // HUD 是硬边语言,饼图扇区不倒角;LED/经典圆润
                                    .cornerRadius(settings.isHUD ? 0 : 3)
                            }
                            .chartLegend(.hidden)
                            // LED:放射状暗缝把圆环切成一圈灯格(像转速表的 LED 环)。
                            // 注意是**沿角度**切,不是沿半径——同心环会把圆环切成弹簧线圈,很难看。
                            .overlay {
                                if settings.isLED {
                                    ZStack {
                                        ForEach(0..<36, id: \.self) { i in
                                            Rectangle()
                                                .fill(LED.bg)
                                                .frame(width: 2.2, height: 24)
                                                .offset(y: -48)
                                                .rotationEffect(.degrees(Double(i) * 10))
                                        }
                                    }
                                    .allowsHitTesting(false)
                                }
                            }
                            .frame(width: 120, height: 120)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(models) { s in
                                Button {
                                    if usage.filter.models == [s.key] { usage.filter.models = [] }
                                    else { usage.filter.models = [s.key] }
                                } label: {
                                    HStack(spacing: 7) {
                                    // HUD 用方块,LED/经典用圆点(LED 的圆点带辉光)
                                    if settings.isHUD {
                                        Rectangle().fill(SeriesColor.color(for: s.key)).frame(width: 7, height: 7)
                                    } else {
                                        Circle().fill(SeriesColor.color(for: s.key)).frame(width: 8, height: 8)
                                            .shadow(color: settings.isLED
                                                    ? SeriesColor.color(for: s.key).opacity(0.8) : .clear, radius: 3)
                                    }
                                    Text(shortModel(s.key))
                                        .font(settings.isLED ? LED.display(11, .medium) : .caption)
                                        .foregroundStyle(settings.isLED ? LED.text
                                                         : (settings.isHUD ? HUD.text : Color.primary))
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(settings.currencyStr(s.costUSD))
                                        .font(settings.isLED ? LED.mono(10, .semibold)
                                              : (settings.isHUD ? HUD.mono(10, .medium) : .system(.caption, design: .monospaced)))
                                        .foregroundStyle(settings.isLED ? LED.amber
                                                         : (settings.isHUD ? HUD.text : Color.primary))
                                    Text(String(format: "%.0f%%", s.share * 100))
                                        .font(settings.isLED ? LED.mono(9) : (settings.isHUD ? HUD.mono(9) : .caption2))
                                        .foregroundStyle(settings.isLED ? LED.dim
                                                         : (settings.isHUD ? HUD.dim : Color.secondary))
                                        .frame(width: 34, alignment: .trailing)
                                    Image(systemName: usage.filter.models.contains(s.key)
                                          ? "line.3.horizontal.decrease.circle.fill"
                                          : "line.3.horizontal.decrease.circle")
                                        .font(.system(size: 9))
                                        .foregroundStyle(usage.filter.models.contains(s.key)
                                                         ? themeAccent() : Color.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .help("点击筛选该模型，再点一次取消")
                                .accessibilityLabel("筛选模型 \(shortModel(s.key))，成本 \(settings.currencyStr(s.costUSD))，占比 \(String(format: "%.0f", s.share * 100))%")
                                .accessibilityAddTraits(usage.filter.models.contains(s.key) ? .isSelected : [])
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 项目 / 工具排名(点击项目下钻)

private struct GroupRankingCard: View {
    @EnvironmentObject var usage: UsageStore
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        let projects = Array(usage.dashboard.byProject.prefix(6))
        let maxCost = projects.first?.costUSD ?? 1
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "按项目", icon: "folder")
                if projects.isEmpty {
                    EmptyLabel()
                } else {
                    VStack(spacing: 8) {
                        ForEach(projects) { s in
                            Button {
                                if usage.filter.projects == [s.key] { usage.filter.projects = [] }
                                else { usage.filter.projects = [s.key] }
                            } label: {
                                rankRow(name: settings.projectName(s.key), cost: s.costUSD,
                                        share: s.share,
                                        frac: maxCost > 0 ? s.costUSD / maxCost : 0,
                                        selected: usage.filter.projects.contains(s.key))
                            }
                            .buttonStyle(PressableButtonStyle())
                            .help("点击筛选该项目，再点一次取消")
                            .accessibilityLabel("筛选项目 \(settings.projectName(s.key))，成本 \(settings.currencyStr(s.costUSD))，占比 \(String(format: "%.0f", s.share * 100))%")
                            .accessibilityAddTraits(usage.filter.projects.contains(s.key) ? .isSelected : [])
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rankRow(name: String, cost: Double, share: Double,
                         frac: Double, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name)
                    .font(settings.isLED ? LED.display(11, .medium) : .caption)
                    .lineLimit(1)
                    .foregroundStyle(rowNameColor(selected))
                Spacer(minLength: 8)
                Text(settings.currencyStr(cost))
                    .font(settings.isLED ? LED.mono(10)
                          : (settings.isHUD ? HUD.mono(10) : .system(.caption, design: .monospaced)))
                    .foregroundStyle(settings.isLED ? LED.dim
                                     : (settings.isHUD ? HUD.dim : Color.secondary))
                Text(String(format: "%.0f%%", share * 100))
                    .font(settings.isLED ? LED.mono(9) : (settings.isHUD ? HUD.mono(9) : .caption2))
                    .foregroundStyle(settings.isLED ? LED.faint
                                     : (settings.isHUD ? HUD.faint : Color.secondary))
                    .frame(width: 34, alignment: .trailing)
                Image(systemName: selected
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(selected ? themeAccent() : Color.secondary)
            }
            // LED 用灯珠条(不占 GeometryReader,自己就会撑满);HUD/经典是连续条
            if settings.isLED {
                LEDGauge(ratio: frac, color: selected ? LED.amber : LED.amber.opacity(0.6), height: 5)
            } else {
                GeometryReader { geo in
                    if settings.isHUD {
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 4)
                            Rectangle().fill(selected ? HUD.cyan : HUD.cyan.opacity(0.5))
                                .frame(width: max(4, geo.size.width * frac), height: 4)
                                .shadow(color: HUD.cyan.opacity(selected ? 0.7 : 0.2), radius: 2)
                        }
                    } else {
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary).frame(height: 5)
                            Capsule().fill(selected ? Color.accentColor : Color.accentColor.opacity(0.55))
                                .frame(width: max(4, geo.size.width * frac), height: 5)
                        }
                    }
                }
                .frame(height: settings.isHUD ? 4 : 5)
            }
        }
        .contentShape(Rectangle())
    }

    private func rowNameColor(_ selected: Bool) -> Color {
        if settings.isLED { return selected ? LED.amber : LED.text }
        if settings.isHUD { return selected ? HUD.cyan : HUD.text }
        return selected ? Color.accentColor : Color.primary
    }
}

// MARK: - 共享:模型短名 + 显示设置菜单

func shortModel(_ name: String) -> String {
    name.replacingOccurrences(of: "claude-", with: "")
        .replacingOccurrences(of: "-20([0-9]{6}|[0-9]{2}-[0-9]{2}-[0-9]{2})$",
                              with: "", options: .regularExpression)
}

/// 计量单位 / 货币 / 主题 / 提醒设置菜单(弹窗与监控台共用)
struct DisplaySettingsMenu: View {
    var unifiedToolbar = false
    @ObservedObject private var settings = DisplaySettings.shared
    @ObservedObject private var alerts = NotificationManager.shared
    @ObservedObject private var updates = UpdateController.shared
    @EnvironmentObject private var quota: QuotaStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Menu {
            // 主题切换:所有界面(弹窗/二级页/监控台/灵动岛)一起换肤
            Picker("主题", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
            }
            Divider()
            Picker("Token 单位", selection: $settings.tokenUnit) {
                ForEach(TokenUnitMode.allCases) { Text($0.label).tag($0) }
            }
            Picker("货币", selection: $settings.currency) {
                ForEach(CurrencyMode.allCases) { Text($0.label).tag($0) }
            }
            if settings.currency == .cny {
                Divider()
                Text("汇率 1 USD = \(String(format: "%.2f", settings.usdToCny)) CNY")
                Button("汇率 7.0") { settings.usdToCny = 7.0 }
                Button("汇率 7.2") { settings.usdToCny = 7.2 }
                Button("汇率 7.4") { settings.usdToCny = 7.4 }
            }
            Divider()
            Toggle("刘海常驻油量表", isOn: Binding(
                get: { NotchDock.shared.enabled },
                set: { NotchDock.shared.enabled = $0 }))
            Toggle("Claude 额度（实验）", isOn: Binding(
                get: { quota.claudeAccessEnabled },
                set: { quota.setClaudeAccessEnabled($0) }))
            Toggle("额度重置提醒", isOn: Binding(
                get: { alerts.enabled },
                set: { alerts.setAlertsEnabled($0) }))
            Toggle("等价成本提醒", isOn: Binding(
                get: { alerts.costAlertsEnabled },
                set: { alerts.setCostAlertsEnabled($0) }))
            if alerts.costAlertsEnabled {
                Picker("每小时提醒线", selection: $alerts.hourlyThresholdUSD) {
                    ForEach([10.0, 20.0, 50.0, 100.0], id: \.self) { amount in
                        Text(settings.currencyStr(amount) + "/小时").tag(amount)
                    }
                }
                Picker("每日提醒线", selection: $alerts.dailyThresholdUSD) {
                    ForEach([50.0, 100.0, 250.0, 500.0], id: \.self) { amount in
                        Text(settings.currencyStr(amount) + "/天").tag(amount)
                    }
                }
                Text("阈值按美元保存，界面会换算为当前货币")
            }
            Toggle("隐私模式（隐藏项目名）", isOn: $settings.privacyMode)
            Toggle("菜单栏显示额度", isOn: $settings.showQuotaInMenuBar)
            Button("预览刘海提醒") {
                NotchController.shared.flash(
                    NotchAlert(icon: "checkmark.circle.fill",
                               title: "Claude · 5 小时额度已重置",
                               subtitle: "满血复活,可以继续了 🎉",
                               tint: .green),
                    duration: 6, sound: true)
            }
            Divider()
            Button("社区排行榜…") { openWindow(id: "leaderboard") }
            Button("检查更新…") { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
            Menu("关于 TokenMini") {
                Text("版本 \(AppInfo.displayVersion)")
                Button("打开官网") { NSWorkspace.shared.open(AppInfo.homepage) }
                Button("隐私说明") { NSWorkspace.shared.open(AppInfo.privacy) }
                Button("开源许可与源码") { NSWorkspace.shared.open(AppInfo.source) }
                Divider()
                Button("退出 TokenMini") { NSApp.terminate(nil) }
            }
        } label: {
            if unifiedToolbar {
                DashboardToolbarLabel(title: "外观", icon: "slider.horizontal.3")
            } else if settings.isPrism {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(Prism.silver)
                    Text("外观")
                        .foregroundColor(Prism.silver)
                }.font(Prism.label(11))
            } else {
                Image(systemName: "slider.horizontal.3")
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .modifier(DashboardAppearanceChrome(unified: unifiedToolbar))
        .accessibilityLabel("显示与主题设置")
        .help("显示与主题设置")
        .fixedSize()
    }
}
