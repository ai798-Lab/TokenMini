import SwiftUI

/// LED 主题·简单模式首页(默认):回答普通人三个问题——电脑扛得住吗 / 额度还能用多久 / 花了多少钱。
/// 不出现 token/burn rate 等术语。(健康评估逻辑共享 ComputerHealth,话术与 HUD/经典版逐字一致)
struct LEDSimpleHomeView: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var quota: QuotaStore
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        // 每分钟刷新倒计时(额度数据本身 90s/5min 更新)
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            VStack(alignment: .leading, spacing: 10) {
                LEDHealthLightRow()
                quotaSection(now: now)
                spendRow
            }
        }
    }

    // MARK: 额度油量条

    @ViewBuilder
    private func quotaSection(now: Date) -> some View {
        if quota.quotas.isEmpty {
            HStack(spacing: 8) {
                if quota.lastRefresh == nil { ProgressView().controlSize(.small) }
                else { Image(systemName: "exclamationmark.circle").foregroundStyle(LED.amber) }
                Text(quota.lastRefresh == nil ? L10n.text("正在读取额度…") : L10n.text("未读取到额度,稍后自动重试"))
                    .font(LED.display(11, .medium)).foregroundStyle(LED.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } else {
            VStack(spacing: 10) {
                ForEach(quota.quotas) { q in LEDQuotaCard(quota: q, now: now) }
            }
        }
    }

    // MARK: 花费跑道(琥珀 = 金钱)

    private var spendRow: some View {
        LEDPanel(tint: LED.amber, padding: 12) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    spendCell("24H", L10n.text("24 小时花费"), settings.currencyStr(usage.last24Hours.totalCostUSD))
                    Rectangle().fill(LED.amber.opacity(0.28)).frame(width: 1, height: 42)
                    spendCell("THIS MONTH", L10n.text("本月花费"), settings.currencyStr(usage.thisMonth.totalCostUSD))
                }
                LEDChevrons(pointingRight: true, count: 5, tint: LED.amber, size: 6)
            }
        }
    }

    private func spendCell(_ code: String, _ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            LEDCaption(text: code, tint: LED.amber, size: 8)
            Text(title).font(LED.display(9, .medium)).foregroundStyle(LED.dim)
            SevenSegmentText(text: value, height: 22, color: LED.amber)
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 秒数 → 七段倒计时（显示数字不依赖界面语言）

enum SegTime {
    /// 与 QuotaFormat.duration 使用相同的分钟/小时/天分档；不足一分钟交给本地化文字。
    static func from(seconds: TimeInterval) -> (digits: String, unit: String)? {
        guard seconds.isFinite, seconds >= 60, seconds < Double(Int.max) else { return nil }
        let total = Int(seconds)
        let days = total / 86400, hours = (total % 86400) / 3600, minutes = (total % 3600) / 60
        if days > 0 {
            return (String(format: "%d:%02d", days, hours), L10n.text("天 : 小时"))
        }
        if hours > 0 {
            return (String(format: "%d:%02d", hours, minutes), L10n.text("小时 : 分钟"))
        }
        return (String(minutes), L10n.text("分钟"))
    }
}

// MARK: - 单个工具的额度卡(本页主角:一块 LED 显示屏)

private struct LEDQuotaCard: View {
    let quota: ToolQuota
    let now: Date

    /// 屏色跟随最紧张窗口的余量(与 HUD/经典版同口径:0.6 转琥珀、0.85 转红)
    private var tint: Color {
        let worst = quota.windows.map { $0.effectiveUsed(now: now) / 100 }.max() ?? 0
        return LED.level(worst)
    }

    var body: some View {
        LEDPanel(tint: tint, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                header
                ForEach(quota.windows) { w in LEDQuotaBar(window: w, now: now) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: quota.tool == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.7), radius: 3)
            Text(quota.tool.label)
                .font(LED.display(13, .bold))
                .foregroundStyle(LED.text)
            if let plan = quota.plan {
                Text(plan.uppercased())
                    .font(LED.mono(8, .bold))
                    .kerning(0.6)
                    .foregroundStyle(LED.dim)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(LED.chrome))
            }
            Spacer(minLength: 4)
            if !quota.authoritative {
                Text(L10n.text("估算")).font(LED.display(9, .medium)).foregroundStyle(LED.faint)
            }
        }
    }
}

/// 一条额度:标题 + 大七段剩余时间 + 灯珠条 + "还能用 X · 几点重置"
private struct LEDQuotaBar: View {
    let window: QuotaWindow
    let now: Date

    private var used: Double { window.effectiveUsed(now: now) / 100 }
    private var color: Color { LED.level(used) }
    private var isReset: Bool { window.hasReset(now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.kind.label).font(LED.display(10, .medium)).foregroundStyle(LED.dim)
                Spacer()
                Text(isReset ? L10n.text("满额可用") : L10n.text("已用 \(Int(window.usedPercent))%"))
                    .font(LED.mono(10, .bold))
                    .foregroundStyle(isReset ? LED.green : color)
            }
            readout
            LEDGauge(ratio: isReset ? 0 : used, color: color, height: 7)
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 8)).foregroundStyle(LED.faint)
                Text(isReset
                     ? L10n.text("已重置,随时可用")
                     : L10n.text("还能用 \(QuotaFormat.duration(window.remaining(now: now))) · \(QuotaFormat.resetClock(window.resetsAt)) 重置"))
                    .font(LED.display(9, .medium)).foregroundStyle(LED.dim)
            }
        }
    }

    /// 主角读数。中文(满额可用 / <1分钟)七段管显示不了,回退成同色圆体大字 + 同款辉光。
    @ViewBuilder
    private var readout: some View {
        let remaining = window.remaining(now: now)
        let durationText = QuotaFormat.duration(remaining)
        Group {
            if isReset {
                VStack(spacing: 4) {
                    glowText(L10n.text("满额可用"), size: 22, color: LED.green)
                    LEDCaption(text: L10n.text("已就绪"), tint: LED.green, size: 7)
                }
            } else if let t = SegTime.from(seconds: remaining) {
                VStack(spacing: 5) {
                    LEDCaption(text: L10n.text("剩余时间"), tint: color.opacity(0.75), size: 7)
                    SevenSegmentText(text: t.digits, height: 34, color: color)
                        .frame(height: 34)
                    LEDCaption(text: t.unit, tint: color, size: 7)
                }
            } else {
                VStack(spacing: 4) {
                    glowText(durationText, size: 20, color: color)
                    LEDCaption(text: L10n.text("剩余时间"), tint: color, size: 7)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func glowText(_ s: String, size: CGFloat, color: Color) -> some View {
        Text(s)
            .font(LED.display(size, .heavy))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.9), radius: size * 0.16)
            .shadow(color: color.opacity(0.4), radius: size * 0.5)
    }
}

// MARK: - 电脑一盏灯

struct LEDHealthLightRow: View {
    @EnvironmentObject var system: SystemMonitor

    var body: some View {
        let h = ComputerHealth.evaluate(system)
        let c = ledColor(h.level)
        LEDPanel(tint: c, padding: 10) {
            HStack(spacing: 10) {
                LEDBigLamp(color: c, pulses: h.level != .good)
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.title).font(LED.display(13, .bold)).foregroundStyle(LED.text)
                    Text(h.detail).font(LED.display(9, .medium)).foregroundStyle(LED.dim).lineLimit(1)
                }
                Spacer(minLength: 6)
                miniStat("CPU", String(format: "%02.0f", system.cpu.totalUsage * 100),
                         LED.level(system.cpu.totalUsage))
                miniStat("MEM", String(format: "%02.0f", system.memory.usageRatio * 100),
                         LED.level(system.memory.usageRatio, warn: 0.82, bad: 0.92))
                if let t = system.sensors.cpuTemp {
                    miniStat("TMP", String(format: "%02.0f", t),
                             t > 92 ? LED.red : (t > 82 ? LED.amber : LED.green))
                }
            }
        }
    }

    private func miniStat(_ code: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            SevenSegmentText(text: value, height: 15, color: color)
                .frame(height: 15)
            LEDCaption(text: code, tint: color.opacity(0.8), size: 7)
        }
        .frame(minWidth: 28)
    }

    private func ledColor(_ level: ComputerHealth.Level) -> Color {
        switch level {
        case .good: return LED.green
        case .warn: return LED.amber
        case .critical: return LED.red
        }
    }
}

/// 仪表盘上那颗大指示灯。只在异常时脉冲——一切正常还闪个不停等于天天狼来了。
private struct LEDBigLamp: View {
    let color: Color
    let pulses: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.14)).frame(width: 30, height: 30)
            Circle().fill(color.opacity(0.28)).frame(width: 20, height: 20)
            Circle().fill(color).frame(width: 12, height: 12)
                .shadow(color: color.opacity(0.95), radius: 5)
                .shadow(color: color.opacity(0.5), radius: 12)
        }
        .opacity(dimmed ? 0.45 : 1)
        // 健康等级会在视图存活期间变化,onAppear 一次不够,必须跟着 pulses 起停
        .onAppear { sync() }
        .onChange(of: pulses) { _, _ in sync() }
    }

    private func sync() {
        guard pulses && !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) { dimmed = false }
            return
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
    }
}
