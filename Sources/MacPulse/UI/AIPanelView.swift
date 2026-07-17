import SwiftUI
import Charts

/// AI 用量页签(弹窗一瞥):今日花费 / 本月与预估 / 7 天趋势 / 按模型明细 + 打开监控台
struct HUDAIPanelView: View {
    @EnvironmentObject var usage: UsageStore
    @ObservedObject private var settings = DisplaySettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headline
            trendChart
            modelBreakdown
            openDashboardButton
            Text("数据来自 Claude Code 与 Codex CLI 本地会话记录,费用按官方 API 定价估算")
                .font(.system(size: 8.5))
                .foregroundStyle(HUD.faint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var openDashboardButton: some View {
        Button {
            openWindow(id: "dashboard")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 10))
                Text("打开监控台")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        .buttonStyle(HUDButtonStyle(filled: true, size: 11))
    }

    // MARK: 今日(大读数 + 三格跑道)

    private var headline: some View {
        HUDPanel(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HUDSectionHeader(cn: "今日花费", code: "AI.COST // TODAY",
                                 trailing: AnyView(settingsMenu))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(settings.currencyStr(usage.today.totalCostUSD))
                        .font(HUD.mono(26, .bold))
                        .foregroundStyle(HUD.cyan)
                        .shadow(color: HUD.cyan.opacity(0.35), radius: 8)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.4), value: usage.today.totalCostUSD)
                    Text("\(settings.tokens(usage.today.totalTokens)) tok · \(usage.today.eventCount) 次")
                        .font(HUD.mono(8))
                        .foregroundStyle(HUD.dim)
                }
                Rectangle().fill(HUD.gridline).frame(height: 1)
                HStack(spacing: 0) {
                    stat("近 1 小时", "RATE/H", settings.currencyStr(usage.burnRatePerHourUSD))
                    Rectangle().fill(HUD.gridline).frame(width: 1, height: 24)
                    stat("本月已用", "MTD", settings.currencyStr(usage.thisMonth.totalCostUSD))
                    Rectangle().fill(HUD.gridline).frame(width: 1, height: 24)
                    stat("整月预估", "PROJ", settings.currencyStr(usage.monthProjectionUSD))
                }
            }
        }
    }

    // 计量单位 / 货币 设置(齿轮菜单)
    private var settingsMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: "slider.horizontal.3").font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(HUD.dim)
    }

    private func stat(_ title: String, _ code: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Text(title).font(.system(size: 8)).foregroundStyle(HUD.dim)
                Text(code).font(HUD.mono(6.5, .medium)).kerning(0.6).foregroundStyle(HUD.faint)
            }
            Text(value).font(HUD.mono(12, .semibold)).foregroundStyle(HUD.text)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 7 天趋势

    @ViewBuilder
    private var trendChart: some View {
        HUDPanel(padding: 10, accent: HUD.violet) {
            VStack(alignment: .leading, spacing: 6) {
                HUDSectionHeader(cn: "近 7 天", code: "TREND.7D", accent: HUD.violet)
                if usage.last7Days.isEmpty {
                    // 冷启动全量解析约 30~40 秒,期间给占位而不是空图
                    HStack(spacing: 6) {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text("正在扫描本地会话…")
                            .font(HUD.mono(8))
                            .foregroundStyle(HUD.faint)
                        Spacer()
                    }
                    .frame(height: 90)
                } else {
                    chartBody
                }
            }
        }
    }

    private var chartBody: some View {
        Chart(usage.last7Days) { d in
                BarMark(
                    x: .value("日期", String(d.day.suffix(5))),
                    y: .value("花费", d.costUSD),
                    width: .ratio(0.55)
                )
                .foregroundStyle(
                    LinearGradient(colors: [HUD.cyan, HUD.cyan.opacity(0.25)],
                                   startPoint: .top, endPoint: .bottom))
            }
            // 字符串 x 轴是分类轴,显式钉住 domain 顺序,不依赖隐式的数据出现顺序
            .chartXScale(domain: usage.last7Days.map { String($0.day.suffix(5)) })
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine().foregroundStyle(HUD.gridline)
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(settings.currencyCompact(d))
                                .font(HUD.mono(7)).foregroundStyle(HUD.faint)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(HUD.mono(7))
                        .foregroundStyle(HUD.faint)
                }
            }
            .frame(height: 90)
    }

    // MARK: 按模型

    @ViewBuilder
    private var modelBreakdown: some View {
        let models = usage.thisMonth.byModel
            .sorted { $0.value.costUSD > $1.value.costUSD }
            .prefix(5)
        if !models.isEmpty {
            HUDPanel(padding: 10, accent: HUD.mint) {
                VStack(alignment: .leading, spacing: 4) {
                    HUDSectionHeader(cn: "本月按模型", code: "MODEL.MTD", accent: HUD.mint)
                    ForEach(Array(models), id: \.key) { name, m in
                        HStack {
                            Rectangle().fill(SeriesColor.color(for: name))
                                .frame(width: 5, height: 5)
                            Text(shortModel(name))
                                .font(.system(size: 10)).foregroundStyle(HUD.text).lineLimit(1)
                            Spacer()
                            Text(settings.tokens(m.inputTokens + m.outputTokens
                                + m.cacheCreationTokens + m.cacheReadTokens))
                                .font(HUD.mono(8))
                                .foregroundStyle(HUD.faint)
                                .frame(width: 64, alignment: .trailing)
                            Text(settings.currencyStr(m.costUSD))
                                .font(HUD.mono(9, .medium))
                                .foregroundStyle(HUD.dim)
                                .frame(width: 72, alignment: .trailing)
                        }
                        .padding(.vertical, 1)
                        .hudRowHover()
                    }
                }
            }
        }
    }

    // MARK: 工具

    private func shortModel(_ name: String) -> String {
        name.replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20[0-9]{6}$", with: "", options: .regularExpression)
    }
}
