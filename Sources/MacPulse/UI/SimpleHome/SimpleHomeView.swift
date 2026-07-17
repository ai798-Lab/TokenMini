import SwiftUI

/// 简单模式首页(默认):回答普通人三个问题——还能用多久 / 会不会超支 / 电脑扛得住吗。
/// 不出现 token/burn rate 等术语。HUD 皮肤,但话术保持大白话。
struct HUDSimpleHomeView: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var quota: QuotaStore
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        // 每分钟刷新倒计时(额度数据本身 90s/5min 更新)
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            VStack(alignment: .leading, spacing: 10) {
                HUDHealthLightRow()
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
                else { Image(systemName: "exclamationmark.circle").foregroundStyle(HUD.amber) }
                Text(quota.lastRefresh == nil ? "正在读取额度…" : "未读取到额度,稍后自动重试")
                    .font(.caption).foregroundStyle(HUD.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } else {
            VStack(spacing: 8) {
                ForEach(quota.quotas) { q in QuotaCard(quota: q, now: now) }
            }
        }
    }

    // MARK: 花费跑道

    private var spendRow: some View {
        HUDPanel(padding: 8, accent: HUD.violet) {
            HStack(spacing: 0) {
                spendCell("今日花费", "COST.TODAY", settings.currencyStr(usage.today.totalCostUSD))
                Rectangle().fill(HUD.gridline).frame(width: 1, height: 30)
                spendCell("本月花费", "COST.MONTH", settings.currencyStr(usage.thisMonth.totalCostUSD))
            }
        }
    }

    private func spendCell(_ title: String, _ code: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 9)).foregroundStyle(HUD.dim)
                Text(code).font(HUD.mono(7, .medium)).kerning(0.8).foregroundStyle(HUD.faint)
            }
            Text(value)
                .font(HUD.mono(17, .bold))
                .foregroundStyle(HUD.text)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 单个工具的额度卡

private struct QuotaCard: View {
    let quota: ToolQuota
    let now: Date

    private var accent: Color {
        // 卡片括号跟随最紧张窗口的余量色
        let worst = quota.windows.map { $0.effectiveUsed(now: now) / 100 }.max() ?? 0
        return HUD.quota(worst)
    }

    var body: some View {
        HUDPanel(padding: 10, accent: accent) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: quota.tool == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 9)).foregroundStyle(accent)
                    Text(quota.tool.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HUD.text)
                    if let plan = quota.plan {
                        HUDChip(text: plan.uppercased(), color: HUD.cyan)
                    }
                    Spacer()
                    if !quota.authoritative {
                        Text("估算").font(HUD.mono(8)).foregroundStyle(HUD.faint)
                    }
                }
                ForEach(quota.windows) { w in QuotaBar(window: w, now: now) }
            }
        }
    }
}

/// 一条额度电量条:标题 + LED 油量 + "还能用 X · 几点重置"
private struct QuotaBar: View {
    let window: QuotaWindow
    let now: Date

    private var used: Double { window.effectiveUsed(now: now) / 100 }
    private var color: Color { HUD.quota(used) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.kind.label).font(.system(size: 10)).foregroundStyle(HUD.dim)
                Spacer()
                Text(window.hasReset(now: now) ? "满额可用" : "已用 \(Int(window.usedPercent))%")
                    .font(HUD.mono(10, .semibold))
                    .foregroundStyle(window.hasReset(now: now) ? HUD.green : color)
            }
            HUDGauge(ratio: window.hasReset(now: now) ? 0 : used, color: color)
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 8)).foregroundStyle(HUD.faint)
                Text(window.hasReset(now: now)
                     ? "已重置,随时可用"
                     : "还能用 \(QuotaFormat.duration(window.remaining(now: now))) · \(QuotaFormat.resetClock(window.resetsAt)) 重置")
                    .font(.system(size: 9)).foregroundStyle(HUD.dim)
            }
        }
    }
}

// MARK: - 电脑一盏灯

struct HUDHealthLightRow: View {
    @EnvironmentObject var system: SystemMonitor

    var body: some View {
        let h = ComputerHealth.evaluate(system)
        HUDPanel(padding: 10, accent: hudColor(h.level)) {
            HStack(spacing: 10) {
                HUDStatusDot(color: hudColor(h.level), size: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(HUD.text)
                    Text(h.detail).font(.system(size: 9)).foregroundStyle(HUD.dim).lineLimit(1)
                }
                Spacer()
                miniStat("CPU", String(format: "%02.0f", system.cpu.totalUsage * 100),
                         HUD.load(system.cpu.totalUsage))
                miniStat("MEM", String(format: "%02.0f", system.memory.usageRatio * 100),
                         HUD.load(system.memory.usageRatio, warn: 0.82, bad: 0.92))
                if let t = system.sensors.cpuTemp {
                    miniStat("TMP", String(format: "%02.0f", t),
                             t > 92 ? HUD.red : (t > 82 ? HUD.amber : HUD.cyan))
                }
            }
        }
    }

    private func miniStat(_ code: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(code).font(HUD.mono(7, .medium)).kerning(0.8).foregroundStyle(HUD.faint)
            Text(value).font(HUD.mono(12, .bold)).foregroundStyle(color)
        }
        .frame(minWidth: 24)
    }

    private func hudColor(_ level: ComputerHealth.Level) -> Color {
        switch level {
        case .good: return HUD.green
        case .warn: return HUD.amber
        case .critical: return HUD.red
        }
    }
}

/// 把系统监控收敛成红黄绿灯 + 大白话
enum ComputerHealth {
    enum Level { case good, warn, critical
        var color: Color { self == .good ? .green : (self == .warn ? .orange : .red) }
    }
    struct Result { let level: Level; let title: String; let detail: String; var color: Color { level.color } }

    @MainActor
    static func evaluate(_ s: SystemMonitor) -> Result {
        let memPressure = s.memory.pressure
        let cpu = s.cpu.totalUsage
        let temp = s.sensors.cpuTemp ?? 0
        let diskFreeRatio = s.diskSpace.total > 0 ? 1 - s.diskSpace.usedRatio : 1

        var issues: [String] = []
        var level: Level = .good
        func bump(_ l: Level) { if l == .critical { level = .critical } else if l == .warn && level == .good { level = .warn } }

        if memPressure >= 1 { bump(.critical); issues.append("内存压力很高") }
        else if memPressure >= 0.8 { bump(.warn); issues.append("内存压力偏高") }
        if temp > 92 { bump(.critical); issues.append("CPU 很烫") }
        else if temp > 82 { bump(.warn); issues.append("CPU 有点热") }
        if cpu > 0.9 { bump(.warn); issues.append("CPU 满载") }
        if diskFreeRatio < 0.05 { bump(.critical); issues.append("磁盘快满了") }
        else if diskFreeRatio < 0.1 { bump(.warn); issues.append("磁盘空间不多") }

        switch level {
        case .good: return Result(level: .good, title: "电脑一切正常", detail: "CPU、内存、温度都很健康")
        case .warn: return Result(level: .warn, title: "电脑有点吃紧", detail: issues.joined(separator: " · "))
        case .critical: return Result(level: .critical, title: "电脑该歇歇了", detail: issues.joined(separator: " · "))
        }
    }
}
