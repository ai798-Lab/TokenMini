import SwiftUI

/// 经典主题·简单模式首页:回答普通人三个问题——还能用多久 / 会不会超支 / 电脑扛得住吗。
/// 不出现 token/burn rate 等术语。(健康评估逻辑共享 ComputerHealth)
struct ClassicSimpleHomeView: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var quota: QuotaStore
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        // 每分钟刷新倒计时(额度数据本身 90s/5min 更新)
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            VStack(alignment: .leading, spacing: 12) {
                ClassicHealthLightRow()
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
                else { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                Text(quota.lastRefresh == nil ? "正在读取额度…" : "未读取到额度,稍后自动重试")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } else {
            VStack(spacing: 10) {
                ForEach(quota.quotas) { q in ClassicQuotaCard(quota: q, now: now) }
            }
        }
    }

    // MARK: 花费跑道

    private var spendRow: some View {
        HStack(spacing: 0) {
            spendCell("今日花费", settings.currencyStr(usage.today.totalCostUSD))
            Divider().frame(height: 26)
            spendCell("本月花费", settings.currencyStr(usage.thisMonth.totalCostUSD))
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func spendCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 单个工具的额度卡

private struct ClassicQuotaCard: View {
    let quota: ToolQuota
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: quota.tool == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right")
                    .font(.caption).foregroundStyle(.secondary)
                Text(quota.tool.label).font(.subheadline.weight(.semibold))
                if let plan = quota.plan {
                    Text(plan.uppercased()).font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.tint.opacity(0.15), in: Capsule()).foregroundStyle(.tint)
                }
                Spacer()
                if !quota.authoritative {
                    Text("估算").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            ForEach(quota.windows) { w in ClassicQuotaBar(window: w, now: now) }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 一条额度电量条:标题 + 进度 + "还能用 X · 几点重置"
private struct ClassicQuotaBar: View {
    let window: QuotaWindow
    let now: Date

    private var used: Double { window.effectiveUsed(now: now) / 100 }
    private var color: Color { used >= 0.85 ? .red : (used >= 0.6 ? .orange : .green) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.kind.label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(window.hasReset(now: now) ? "满额可用" : "已用 \(Int(window.usedPercent))%")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(window.hasReset(now: now) ? .green : color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color.gradient)
                        .frame(width: max(4, geo.size.width * used))
                }
            }
            .frame(height: 7)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: used)
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 9)).foregroundStyle(.tertiary)
                Text(window.hasReset(now: now)
                     ? "已重置,随时可用"
                     : "还能用 \(QuotaFormat.duration(window.remaining(now: now))) · \(QuotaFormat.resetClock(window.resetsAt)) 重置")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 电脑一盏灯

struct ClassicHealthLightRow: View {
    @EnvironmentObject var system: SystemMonitor

    var body: some View {
        let h = ComputerHealth.evaluate(system)
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(h.color.opacity(0.18)).frame(width: 34, height: 34)
                Circle().fill(h.color.gradient).frame(width: 14, height: 14)
                    .shadow(color: h.color.opacity(0.6), radius: 4)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(h.title).font(.subheadline.weight(.semibold))
                Text(h.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }
}
