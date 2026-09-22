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
        let filtered = usage.filter != UsageFilter(time: usage.filter.time)
        return PrismDashboardBanner(
            total: ready ? settings.tokens(overview.totalTokens) : "—",
            scope: "\(usage.filter.time.label) · \(filtered ? "当前筛选" : "全部工具")",
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
            HStack(spacing: 10) {
                ThemedSegmented(items: presets.map { ($0, $0.label) },
                                selection: $usage.filter.time)
                Spacer()
                ThemedSegmented(items: DashboardMode.allCases.map { ($0, $0.label) },
                                selection: $settings.dashboardMode, size: 9)
                Button { openWindow(id: "leaderboard") } label: {
                    Label("排行", systemImage: "trophy")
                        .font(settings.isLED ? LED.display(9, .medium)
                              : (settings.isHUD ? HUD.mono(9) : .caption))
                }
                .buttonStyle(ThemedToolbarButtonStyle())
                .foregroundStyle(settings.isDarkSkin ? themeAccent() : Color.accentColor)
                .help("社区排行榜")
                Button { showSources = true } label: {
                    Label("数据源", systemImage: "externaldrive.badge.plus")
                }.buttonStyle(.plain)
                .sheet(isPresented: $showSources) { UsageSourcesView().environmentObject(usage) }
                DisplaySettingsMenu()
                    .foregroundStyle(settings.isLED ? LED.dim
                                     : (settings.isHUD ? HUD.dim : Color.secondary))
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
        }
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

    @ViewBuilder
    private func multiMenu(_ title: String, options: [(key: String, label: String)],
                           selection: Binding<Set<String>>) -> some View {
        let n = selection.wrappedValue.count
        if settings.isDarkSkin {
            menuBody(title, options: options, selection: selection) {
                ThemedMenuLabel(title: title, count: n)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)      // 箭头由 ThemedMenuLabel 自己画,不要系统再叠一个
            .fixedSize()
            .modifier(ThemedMenuChrome(active: n > 0))
            .disabled(options.isEmpty)
            .opacity(options.isEmpty ? 0.4 : 1)
        } else {
            // 经典主题就该是纯系统原生:.bordered 的可点击暗示是系统给的,别自己糊一个更差的
            menuBody(title, options: options, selection: selection) {
                Text(n == 0 ? title : "\(title) · \(n)")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .disabled(options.isEmpty)
        }
    }

    /// 菜单内容(三主题共用,只有 label 外观不同)
    private func menuBody<L: View>(_ title: String, options: [(key: String, label: String)],
                                   selection: Binding<Set<String>>,
                                   @ViewBuilder label: () -> L) -> some View {
        Menu {
            if selection.wrappedValue.isEmpty == false {
                Button("清除") { selection.wrappedValue = [] }
                Divider()
            }
            ForEach(options, id: \.key) { opt in
                Toggle(opt.label, isOn: Binding(
                    get: { selection.wrappedValue.contains(opt.key) },
                    set: { on in
                        if on { selection.wrappedValue.insert(opt.key) }
                        else { selection.wrappedValue.remove(opt.key) }
                    }))
            }
        } label: { label() }
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

    private struct Bar: Identifiable { let id = UUID(); let bucket: String; let idx: Int; let series: String; let cost: Double }

    private var bars: [Bar] {
        var out: [Bar] = []
        for p in usage.dashboard.trend {
            if stackByModel {
                for (m, c) in p.byModel where c > 0 {
                    out.append(Bar(bucket: p.label, idx: p.id, series: shortModel(m), cost: c))
                }
            } else {
                let b = p.byType
                let pairs: [(String, Double)] = [("输入", b.input), ("输出", b.output),
                                                 ("缓存写", b.cacheWrite), ("缓存读", b.cacheRead)]
                for (name, c) in pairs where c > 0 { out.append(Bar(bucket: p.label, idx: p.id, series: name, cost: c)) }
            }
        }
        return out
    }

    /// 图例里出现的系列(顺序稳定,颜色与图表同源:都走 SeriesColor)
    /// 分类轴 domain:标签在聚合层已保证唯一,这里再去一次重——重复的分类 domain 会让
    /// Swift Charts 把两个不同时段的柱子叠到同一根上,严重时直接 trap。
    private var xDomain: [String] {
        var seen = Set<String>()
        return usage.dashboard.trend.compactMap { seen.insert($0.label).inserted ? $0.label : nil }
    }

    private var series: [String] {
        var seen = Set<String>()
        return bars.compactMap { seen.insert($0.series).inserted ? $0.series : nil }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "等价成本趋势", icon: "chart.bar.xaxis",
                              trailing: AnyView(
                                ThemedSegmented(items: [(true, "按模型"), (false, "成本构成")],
                                                selection: $stackByModel, size: 9)))
                if usage.dashboard.trend.allSatisfy({ $0.costUSD == 0 }) {
                    emptyHint
                } else {
                    Group {
                        if settings.isLED { ledChart }
                        else if settings.isHUD { hudChart }
                        else { classicChart }
                    }
                    // 图表不参与任何隐式动画:顶部分段控件是 withAnimation 切换的,那一拍
                    // Charts 会给旧柱子做退场过渡,而聚合结果换了一套分类轴 domain,
                    // 退场中的旧柱在新 domain 里找不到位置 → Charts 内部 trap(监控台闪退元凶)。
                    .transaction { $0.animation = nil }
                    // 自带图例是系统字体+圆点,在 HUD/LED 下很出戏;统一换自绘图例
                    ThemedChartLegend(series: series)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// 共享的柱状图主体(轴样式按主题分开配)。
    /// 直接给 SeriesColor 的色,不用 foregroundStyle(by:) —— 后者按数据出现顺序自动配色,
    /// 会和自绘图例对不上;同 x 的柱子仍会自动堆叠,不依赖 by:。
    private var chartBase: some ChartContent {
        ForEach(bars) { b in
            BarMark(x: .value("时间", b.bucket), y: .value("花费", b.cost))
                .foregroundStyle(SeriesColor.color(for: b.series))
        }
    }

    /// LED 版柱子:窄一点、圆角、顶端带一点辉光——读起来像一排 LED 灯柱而不是通用柱状图
    private var ledChartBase: some ChartContent {
        ForEach(bars) { b in
            BarMark(x: .value("时间", b.bucket), y: .value("花费", b.cost), width: .ratio(0.55))
                .foregroundStyle(SeriesColor.color(for: b.series))
                .cornerRadius(2)
        }
    }

    private var ledChart: some View {
        Chart { ledChartBase }
            .chartLegend(.hidden)
            .chartXScale(domain: xDomain)
            // 灯格罩:把柱子切成一格格灯珠,而不是一根实心色块
            .chartPlotStyle { plot in
                plot.background(LED.amber.opacity(0.02))
                    .overlay { LEDCellMask() }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine().foregroundStyle(LED.amber.opacity(0.07))
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(settings.currencyCompact(d)).font(LED.din(10)).foregroundStyle(LED.faint)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 8)) {
                    AxisValueLabel().font(LED.din(10)).foregroundStyle(LED.faint)
                }
            }
            // 整块图垫一层琥珀辉光,而不是给每根柱子加阴影(那样会糊成一片)
            .shadow(color: LED.amber.opacity(0.25), radius: 6)
            .frame(height: 200)
    }

    private var hudChart: some View {
        Chart { chartBase }
            .chartLegend(.hidden)
            .chartXScale(domain: xDomain)
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine().foregroundStyle(HUD.gridline)
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(settings.currencyCompact(d)).font(HUD.mono(9)).foregroundStyle(HUD.faint)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 8)) {
                    AxisValueLabel().font(HUD.mono(9)).foregroundStyle(HUD.faint)
                }
            }
            .frame(height: 200)
    }

    private var classicChart: some View {
        Chart { chartBase }
            .chartLegend(.hidden)
            .chartXScale(domain: xDomain)
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text(settings.currencyCompact(d)).font(.caption2) } }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) { AxisValueLabel().font(.caption2) } }
            .frame(height: 200)
    }

    private var emptyHint: some View {
        Text("该范围内无数据")
            .font(settings.isLED ? LED.mono(10) : (settings.isHUD ? HUD.mono(10) : .caption))
            .foregroundStyle(settings.isLED ? LED.faint
                             : (settings.isHUD ? HUD.faint : Color.secondary.opacity(0.6)))
            .frame(maxWidth: .infinity, minHeight: 200)
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
            if settings.isPrism {
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
        .modifier(ThemedMenuChrome())
        .accessibilityLabel("显示与主题设置")
        .help("显示与主题设置")
        .fixedSize()
    }
}
