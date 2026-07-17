import SwiftUI
import Charts

/// LED 主题·AI 用量页签:今日花费 / 本月与预估 / 7 天趋势 / 按模型明细 + 打开监控台
/// 整页统一琥珀色 —— 按 LED 配色规则,金钱/token/用量归琥珀,红只留给系统负载。
struct LEDAIPanelView: View {
    @EnvironmentObject var usage: UsageStore
    @ObservedObject private var settings = DisplaySettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headline
            trendChart
            modelBreakdown
            openDashboardButton
            Text("数据来自 Claude Code 与 Codex CLI 本地会话记录,费用按官方 API 定价估算")
                .font(.system(size: 8))
                .foregroundStyle(LED.faint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: 今日花费大屏(本页主角:全 app 最大的读数)

    private var headline: some View {
        LEDPanel(tint: LED.amber, padding: 14) {
            VStack(spacing: 9) {
                VStack(spacing: 3) {
                    LEDCaption(text: "TODAY · COST", tint: LED.amber)
                    Text("今日花费")
                        .font(LED.display(10, .semibold))
                        .foregroundStyle(LED.dim)
                }
                SevenSegmentText(text: settings.currencyStr(usage.today.totalCostUSD),
                                 height: 40, color: LED.amber)
                Text("\(settings.tokens(usage.today.totalTokens)) tok · \(usage.today.eventCount) 次")
                    .font(LED.mono(8))
                    .foregroundStyle(LED.dim)
                HStack(spacing: 8) {
                    LEDChevrons(pointingRight: false, tint: LED.amber)
                    LEDCaption(text: "LIVE FROM LOCAL SESSIONS", tint: LED.amber.opacity(0.7), size: 7)
                    LEDChevrons(pointingRight: true, tint: LED.amber)
                }
                Rectangle().fill(LED.amber.opacity(0.18)).frame(height: 1)
                HStack(spacing: 0) {
                    stat("近 1 小时", "RATE/H", settings.currencyStr(usage.burnRatePerHourUSD))
                    divider
                    stat("本月已用", "MTD", settings.currencyStr(usage.thisMonth.totalCostUSD))
                    divider
                    stat("整月预估", "PROJ", settings.currencyStr(usage.monthProjectionUSD))
                }
            }
            .frame(maxWidth: .infinity)
            // 设置菜单浮在屏角,不参与居中排版(否则大读数会被挤偏)
            .overlay(alignment: .topTrailing) { settingsMenu }
        }
    }

    private var divider: some View {
        Rectangle().fill(LED.amber.opacity(0.18)).frame(width: 1, height: 30)
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
        .foregroundStyle(LED.dim)
    }

    /// 跑道格:英文代号 + 中文小字 + 七段读数
    private func stat(_ cn: String, _ code: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            LEDCaption(text: code, tint: LED.amber.opacity(0.8), size: 7)
            Text(cn)
                .font(LED.display(8, .medium))
                .foregroundStyle(LED.faint)
            SevenSegmentText(text: value, height: 16, color: LED.amber)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 7 天趋势

    @ViewBuilder
    private var trendChart: some View {
        LEDPanel(tint: LED.amber) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    LEDCaption(text: "LAST 7 DAYS", tint: LED.amber)
                    Text("近 7 天")
                        .font(LED.display(9, .medium))
                        .foregroundStyle(LED.faint)
                }
                if usage.last7Days.isEmpty {
                    // 冷启动全量解析约 30~40 秒,期间给占位而不是空图
                    HStack(spacing: 6) {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text("正在扫描本地会话…")
                            .font(LED.mono(8))
                            .foregroundStyle(LED.faint)
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
                    LinearGradient(colors: [LED.amber, LED.amber.opacity(0.22)],
                                   startPoint: .top, endPoint: .bottom))
                .cornerRadius(3)
            }
            // 字符串 x 轴是分类轴,显式钉住 domain 顺序,不依赖隐式的数据出现顺序
            .chartXScale(domain: usage.last7Days.map { String($0.day.suffix(5)) })
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine().foregroundStyle(LED.faint.opacity(0.18))
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(settings.currencyCompact(d))
                                .font(LED.mono(7)).foregroundStyle(LED.faint)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(LED.mono(7))
                        .foregroundStyle(LED.faint)
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
            LEDPanel(tint: LED.amber) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        LEDCaption(text: "BY MODEL · MTD", tint: LED.amber)
                        Text("本月按模型")
                            .font(LED.display(9, .medium))
                            .foregroundStyle(LED.faint)
                    }
                    ForEach(Array(models), id: \.key) { name, m in
                        HStack(spacing: 6) {
                            // 系列色只用于区分模型,与琥珀主调无关,故保留发光圆点而非改色
                            let c = SeriesColor.color(for: name)
                            Circle().fill(c)
                                .frame(width: 5, height: 5)
                                .shadow(color: c.opacity(0.8), radius: 3)
                            Text(shortModel(name))
                                .font(LED.mono(9, .medium))
                                .foregroundStyle(LED.text)
                                .lineLimit(1)
                            Spacer()
                            Text(settings.tokens(m.inputTokens + m.outputTokens
                                + m.cacheCreationTokens + m.cacheReadTokens))
                                .font(LED.mono(8))
                                .foregroundStyle(LED.faint)
                                .frame(width: 64, alignment: .trailing)
                            Text(settings.currencyStr(m.costUSD))
                                .font(LED.mono(9, .semibold))
                                .foregroundStyle(LED.amber)
                                .frame(width: 72, alignment: .trailing)
                        }
                        .padding(.vertical, 1)
                        .ledRowHover()
                    }
                }
            }
        }
    }

    // MARK: CTA

    private var openDashboardButton: some View {
        Button {
            openWindow(id: "dashboard")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 11, weight: .bold))
                Text("打开监控台")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(LEDGhostButtonStyle(size: 13, prominent: true))
    }
}
