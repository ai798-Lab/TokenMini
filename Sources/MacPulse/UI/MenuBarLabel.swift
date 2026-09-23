import SwiftUI
import AppKit

/// 默认仅显示品牌标志与今日 Token，其他指标由用户自行开启。
struct MenuBarLabel: View {
    @ObservedObject var system: SystemMonitor
    @ObservedObject var usage: UsageStore
    @ObservedObject var quota: QuotaStore
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        // Field widths depend only on user preferences, never live values, so the popover stays anchored.
        Image(nsImage: Self.renderLabel(fields: fields))
            .accessibilityLabel(Text(accessibilityText)).help(accessibilityText)
    }

    private var fields: [(symbol: String?, text: String, width: CGFloat)] {
        var result: [(String?, String, CGFloat)] = []
        if settings.showTokensInMenuBar {
            result.append((nil, usage.lastScan == nil ? "—" : MenuBarTokenFormatter.string(usage.today.totalTokens), 54))
        }
        if settings.showCPUInMenuBar { result.append(("cpu", "\(cpuPercent)", 45)) }
        if settings.showMemoryInMenuBar { result.append(("memorychip", "\(memoryPercent)", 45)) }
        if settings.showCostInMenuBar { result.append((nil, costText, 64)) }
        if let remainingQuota { result.append((nil, remainingQuota >= 0 ? "余\(remainingQuota)%" : "余--%", 51)) }
        return result
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
        var text = "TokenMini"
        if settings.showTokensInMenuBar { text += "，今日 Token " + (usage.lastScan == nil ? "加载中" : MenuBarTokenFormatter.string(usage.today.totalTokens)) }
        if settings.showCPUInMenuBar { text += "，CPU \(cpuPercent)%" }
        if settings.showMemoryInMenuBar { text += "，内存 \(memoryPercent)%" }
        if settings.showCostInMenuBar { text += "，今日 API 等价费用预估 \(costText)，不代表订阅实际扣款" }
        if let remainingQuota {
            text += remainingQuota >= 0 ? "，最紧张额度剩余 \(remainingQuota)%" : "，额度数据加载中"
        }
        return text
    }

    private static func clampedPercent(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return min(100, max(0, Int(value.rounded())))
    }

    private static func renderLabel(fields: [(symbol: String?, text: String, width: CGFloat)]) -> NSImage {
        let size = NSSize(width: 18 + fields.reduce(0) { $0 + $1.width + 5 }, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            BrandImages.menuBar?.draw(in: NSRect(x: 0, y: 2, width: 16, height: 16))
            var x: CGFloat = 23
            for field in fields {
                if let symbol = field.symbol {
                    drawSymbol(symbol, x: x, in: rect)
                    drawText(field.text, x: x + 17, maxWidth: field.width - 17, in: rect)
                } else {
                    drawText(field.text, x: x, maxWidth: field.width, in: rect)
                }
                x += field.width + 5
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
