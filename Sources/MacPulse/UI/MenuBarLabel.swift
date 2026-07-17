import SwiftUI

/// 菜单栏常驻标签:CPU% · 内存% · 今日 AI 花费
struct MenuBarLabel: View {
    @ObservedObject var system: SystemMonitor
    @ObservedObject var usage: UsageStore
    @ObservedObject var quota: QuotaStore
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        // 菜单栏里只支持 Text/Image 的单色渲染,保持紧凑
        Text(labelText)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
    }

    private var labelText: String {
        let cpu = String(format: "%.0f", system.cpu.totalUsage * 100)
        let mem = String(format: "%.0f", system.memory.usageRatio * 100)
        let costStr = settings.currencyCompact(usage.today.totalCostUSD)
        var s = "C\(cpu) M\(mem) \(costStr)"
        // 可选:追加最紧张的额度(已用% + 倒计时),用余额概念
        if settings.showQuotaInMenuBar {
            let now = Date()
            if let w = quota.mostConstrained(now: now), !w.hasReset(now: now) {
                s += " ◔\(Int(w.usedPercent))%"
            }
        }
        return s
    }
}
