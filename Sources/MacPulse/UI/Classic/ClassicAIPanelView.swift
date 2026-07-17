import SwiftUI
import Charts

/// 经典主题·AI 用量页签:今日花费 / 本月与预估 / 7 天趋势 / 按模型明细 + 打开监控台
struct ClassicAIPanelView: View {
    @EnvironmentObject var usage: UsageStore
    @ObservedObject private var settings = DisplaySettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline
            statsRow
            trendChart
            modelBreakdown
            openDashboardButton
            Text("数据来自 Claude Code 与 Codex CLI 本地会话记录,费用按官方 API 定价估算")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var openDashboardButton: some View {
        Button {
            openWindow(id: "dashboard")
        } label: {
            Label("打开监控台", systemImage: "chart.bar.doc.horizontal")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }

    // MARK: 今日

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("今日花费")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                settingsMenu
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(settings.currencyStr(usage.today.totalCostUSD))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.4), value: usage.today.totalCostUSD)
                Text("\(settings.tokens(usage.today.totalTokens)) tokens · \(usage.today.eventCount) 次调用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .foregroundStyle(.secondary)
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat("近 1 小时", settings.currencyStr(usage.burnRatePerHourUSD))
            Divider().frame(height: 24)
            stat("本月已用", settings.currencyStr(usage.thisMonth.totalCostUSD))
            Divider().frame(height: 24)
            stat("整月预估", settings.currencyStr(usage.monthProjectionUSD))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.callout, design: .monospaced).weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 7 天趋势

    @ViewBuilder
    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("近 7 天")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if usage.last7Days.isEmpty {
                // 冷启动全量解析约 30~40 秒,期间给占位而不是空图
                HStack(spacing: 6) {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("正在扫描本地会话…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(height: 90)
            } else {
                chartBody
            }
        }
    }

    private var chartBody: some View {
        Chart(usage.last7Days) { d in
                BarMark(
                    x: .value("日期", String(d.day.suffix(5))),
                    y: .value("花费", d.costUSD)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(3)
            }
            // 字符串 x 轴是分类轴,显式钉住 domain 顺序,不依赖隐式的数据出现顺序
            .chartXScale(domain: usage.last7Days.map { String($0.day.suffix(5)) })
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(settings.currencyCompact(d)).font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.caption2)
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
            VStack(alignment: .leading, spacing: 3) {
                Text("本月按模型")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(models), id: \.key) { name, m in
                    HStack {
                        Text(shortModel(name)).font(.caption).lineLimit(1)
                        Spacer()
                        Text(settings.tokens(m.inputTokens + m.outputTokens
                            + m.cacheCreationTokens + m.cacheReadTokens))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 64, alignment: .trailing)
                        Text(settings.currencyStr(m.costUSD))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
            }
        }
    }
}
