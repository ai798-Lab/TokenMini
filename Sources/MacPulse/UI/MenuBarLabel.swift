import SwiftUI
import AppKit

/// 菜单栏常驻标签：CPU · 内存 · 今日 AI API 等价费用预估。
struct MenuBarLabel: View {
    @ObservedObject var system: SystemMonitor
    @ObservedObject var usage: UsageStore
    @ObservedObject var quota: QuotaStore
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        // MenuBarExtra(.window) 会把弹窗锚定到菜单栏标签的外框。CPU/内存/金额
        // 每次采样都可能改变文本宽度；若让外框跟着变化，打开的弹窗会被系统反复
        // 重新锚定，表现为上下漂移或偶发裁切。部分 macOS 版本会绕过 SwiftUI
        // 的 frame 重新测量 Text，因此仍把内容画进固定尺寸模板图；各字段的位置
        // 固定，但不再用肉眼可见的等宽空格撑宽文本。
        Image(nsImage: Self.renderLabel(cpu: cpuPercent,
                                        memory: memoryPercent,
                                        remainingQuota: remainingQuota))
            .accessibilityLabel(Text(accessibilityText))
            .help(accessibilityText)
    }

    private var cpuPercent: Int {
        Self.clampedPercent(system.cpu.totalUsage * 100)
    }

    private var memoryPercent: Int {
        Self.clampedPercent(system.memory.usageRatio * 100)
    }

    private var costText: String {
        Self.menuCost(usage.today.totalCostUSD,
                      currency: settings.currency,
                      usdToCny: settings.usdToCny)
    }

    /// 菜单栏额度显示“剩余”而不是没有说明的“已用”，避免 85% 到底是好是坏的歧义。
    private var remainingQuota: Int? {
        guard settings.showQuotaInMenuBar else { return nil }
        let now = Date()
        guard let window = quota.mostConstrained(now: now), !window.hasReset(now: now) else {
            return -1
        }
        return Self.clampedPercent(100 - window.usedPercent)
    }

    private var accessibilityText: String {
        var text = "CPU \(cpuPercent)%，内存 \(memoryPercent)%，今日 AI API 等价费用预估 \(costText)，不代表订阅实际扣款"
        if let remainingQuota {
            text += remainingQuota >= 0 ? "，最紧张额度剩余 \(remainingQuota)%" : "，额度数据加载中"
        }
        return text
    }

    private static func clampedPercent(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return min(100, max(0, Int(value.rounded())))
    }

    private static func renderLabel(cpu: Int,
                                    memory: Int,
                                    remainingQuota: Int?) -> NSImage {
        // 菜单栏优先留给系统与其他 app：常驻只显示实时 CPU / 内存，今日费用
        // 放在悬停说明和点击后的首屏。画布仍固定，避免数值变化导致弹窗重锚定。
        let size = NSSize(width: remainingQuota == nil ? 80 : 134, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            // 只让数字等宽，中文、字母和标点继续使用系统比例字形，观感与 macOS
            // 原生菜单栏一致；固定坐标负责稳定布局，不再依赖整串等宽字体。
            drawSymbol("cpu", x: 0, in: rect)
            drawText("\(cpu)", x: 16, maxWidth: 19, in: rect)

            drawSymbol("memorychip", x: 38, in: rect)
            drawText("\(memory)", x: 55, maxWidth: 19, in: rect)

            if let remainingQuota {
                let quotaText = remainingQuota >= 0 ? "余\(remainingQuota)%" : "余--%"
                drawText(quotaText, x: 85, maxWidth: 46, in: rect)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawSymbol(_ name: String, x: CGFloat, in rect: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let symbolRect = NSRect(x: x,
                                y: rect.minY + max(0, (rect.height - symbol.size.height) / 2),
                                width: symbol.size.width,
                                height: symbol.size.height)
        symbol.draw(in: symbolRect)
    }

    private static func drawText(_ text: String,
                                 x: CGFloat,
                                 maxWidth: CGFloat,
                                 in rect: NSRect) {
        let baseSize: CGFloat = 13
        let baseFont = NSFont.monospacedDigitSystemFont(ofSize: baseSize, weight: .medium)
        let baseWidth = NSAttributedString(string: text, attributes: [.font: baseFont]).size().width
        let fittedSize = baseWidth > maxWidth
            ? max(10, baseSize * maxWidth / baseWidth)
            : baseSize
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fittedSize, weight: .medium),
            .foregroundColor: NSColor.black
        ])
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(x: x,
                                    y: rect.minY + max(0, (rect.height - textSize.height) / 2)))
    }

    /// 人民币 1 万以内直接显示完整整数（¥5700），避免菜单栏里的 K 需要二次换算。
    /// 更大的人民币使用“万/亿”；美元继续使用国际通用的 K/M/B。
    private static func menuCost(_ usd: Double,
                                 currency: CurrencyMode,
                                 usdToCny: Double) -> String {
        let converted = currency == .cny ? usd * usdToCny : usd
        let value = max(0, converted.isFinite ? converted : 0)

        if currency == .cny {
            switch value {
            case ..<9.95: return String(format: "¥%.1f", value)
            case ..<9_999.5: return String(format: "¥%.0f", value)
            case ..<99_500: return String(format: "¥%.1f万", value / 10_000)
            case ..<9_995_000: return String(format: "¥%.0f万", value / 10_000)
            case ..<995_000_000: return String(format: "¥%.1f亿", value / 100_000_000)
            default: return String(format: "¥%.0f亿", min(value / 100_000_000, 999))
            }
        }

        switch value {
        case ..<99.95: return String(format: "$%.1f", value)
        case ..<999.5: return String(format: "$%.0f", value)
        case ..<9_950: return String(format: "$%.1fK", value / 1_000)
        case ..<999_500: return String(format: "$%.0fK", value / 1_000)
        case ..<9_950_000: return String(format: "$%.1fM", value / 1_000_000)
        case ..<999_500_000: return String(format: "$%.0fM", value / 1_000_000)
        case ..<9_950_000_000: return String(format: "$%.1fB", value / 1_000_000_000)
        default: return String(format: "$%.0fB", min(value / 1_000_000_000, 999))
        }
    }
}
