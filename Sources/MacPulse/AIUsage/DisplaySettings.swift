import Foundation
import Combine

/// Token 计量单位模式
enum TokenUnitMode: String, CaseIterable, Identifiable {
    case chinese        // 万 / 亿
    case international   // K / M / B
    case auto           // 跟随系统语言
    var id: String { rawValue }
    var label: String {
        switch self {
        case .chinese: return "中文单位"
        case .international: return "M / K"
        case .auto: return "自动"
        }
    }
}

/// 货币模式
enum CurrencyMode: String, CaseIterable, Identifiable {
    case cny            // ¥ 人民币
    case usd            // $ 美金
    var id: String { rawValue }
    var label: String { self == .cny ? "¥ 人民币" : "$ 美金" }
}

/// UI 主题:经典(系统原生风)/ HUD(影视包装 FUI 风)/ LED(复古健身器材仪表风)。
/// 切换必须覆盖所有界面:弹窗及其二三级页面、监控台、灵动岛。
enum AppTheme: String, CaseIterable, Identifiable {
    case prism
    case classic
    case hud
    case led
    var id: String { rawValue }
    var label: String {
        switch self {
        case .prism: return "Prism 光核 · 官网同款"
        case .classic: return "经典"
        case .hud: return "HUD 科幻"
        case .led: return "LED 仪表"
        }
    }
}

enum DashboardMode: String, CaseIterable, Identifiable {
    case overview
    case analysis
    var id: String { rawValue }
    var label: String { self == .overview ? "一眼看懂" : "分析模式" }
}

/// 全局显示设置(计量单位 / 货币 / 汇率),UserDefaults 持久化。
/// 用 @Published + didSet 手动落盘,保证任何视图 @ObservedObject 后能可靠收到变更。
@MainActor
final class DisplaySettings: ObservableObject {
    static let shared = DisplaySettings()

    @Published var tokenUnit: TokenUnitMode { didSet { d.set(tokenUnit.rawValue, forKey: kUnit) } }
    @Published var currency: CurrencyMode { didSet { d.set(currency.rawValue, forKey: kCurrency) } }
    @Published var usdToCny: Double { didSet { d.set(usdToCny, forKey: kRate) } }
    @Published var showTokensInMenuBar: Bool { didSet { d.set(showTokensInMenuBar, forKey: "macpulse.menuBar.tokens") } }
    @Published var showCPUInMenuBar: Bool { didSet { d.set(showCPUInMenuBar, forKey: "macpulse.menuBar.cpu") } }
    @Published var showMemoryInMenuBar: Bool { didSet { d.set(showMemoryInMenuBar, forKey: "macpulse.menuBar.memory") } }
    @Published var showCostInMenuBar: Bool { didSet { d.set(showCostInMenuBar, forKey: "macpulse.menuBar.cost") } }
    @Published var showQuotaInMenuBar: Bool { didSet { d.set(showQuotaInMenuBar, forKey: kQuotaBar) } }
    @Published var theme: AppTheme { didSet { d.set(theme.rawValue, forKey: kTheme) } }
    @Published var dashboardMode: DashboardMode { didSet { d.set(dashboardMode.rawValue, forKey: kDashboardMode) } }
    @Published var privacyMode: Bool { didSet { d.set(privacyMode, forKey: kPrivacyMode) } }

    /// 便捷判断(视图分支用)
    var isPrism: Bool { theme == .prism }
    /// Prism 复用 HUD 数据视图，材质和排版由独立皮肤组件提供。
    var isHUD: Bool { theme == .hud || theme == .prism }
    var isLED: Bool { theme == .led }
    /// 深色系主题(HUD/LED):需要强制暗色 + 自绘滚动条
    var isDarkSkin: Bool { theme != .classic }

    private let d = UserDefaults.standard
    private let kUnit = "macpulse.tokenUnit"
    private let kCurrency = "macpulse.currency"
    private let kRate = "macpulse.usdToCny"
    private let kQuotaBar = "macpulse.showQuotaInMenuBar"
    private let kTheme = "macpulse.theme"
    private let kDashboardMode = "macpulse.dashboardMode"
    private let kPrivacyMode = "macpulse.privacyMode"

    private init() {
        tokenUnit = TokenUnitMode(rawValue: d.string(forKey: kUnit) ?? "") ?? .chinese
        currency = CurrencyMode(rawValue: d.string(forKey: kCurrency) ?? "") ?? .cny
        usdToCny = d.object(forKey: kRate) != nil ? d.double(forKey: kRate) : 7.2
        showTokensInMenuBar = d.object(forKey: "macpulse.menuBar.tokens") as? Bool ?? true
        showCPUInMenuBar = d.bool(forKey: "macpulse.menuBar.cpu")
        showMemoryInMenuBar = d.bool(forKey: "macpulse.menuBar.memory")
        showCostInMenuBar = d.bool(forKey: "macpulse.menuBar.cost")
        showQuotaInMenuBar = d.bool(forKey: kQuotaBar)   // 默认 false
        theme = AppTheme(rawValue: d.string(forKey: kTheme) ?? "") ?? .prism
        dashboardMode = DashboardMode(rawValue: d.string(forKey: kDashboardMode) ?? "") ?? .overview
        // Fresh installs show real project names; preserve an existing opt-in to hide them.
        privacyMode = d.object(forKey: kPrivacyMode) as? Bool ?? false
    }

    func projectName(_ raw: String) -> String {
        ProjectName.display(raw, privacy: privacyMode)
    }

    // MARK: - Token 格式化

    /// 12_345_678 → 中文「1234.6万」/ 国际「12.3M」
    func tokens(_ n: Int) -> String {
        switch effectiveUnit {
        case .chinese: return Self.chineseTokens(n)
        default: return Self.intlTokens(n)
        }
    }

    private var effectiveUnit: TokenUnitMode {
        guard tokenUnit == .auto else { return tokenUnit }
        let lang = Locale.preferredLanguages.first ?? "en"
        return lang.hasPrefix("zh") ? .chinese : .international
    }

    /// 中文大数单位:万(1e4)/ 亿(1e8)
    static func chineseTokens(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1e8 { return String(format: "%.2f亿", v / 1e8) }
        if v >= 1e4 { return String(format: "%.1f万", v / 1e4) }
        return "\(n)"
    }

    static func intlTokens(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1e9 { return String(format: "%.2fB", v / 1e9) }
        if v >= 1e6 { return String(format: "%.1fM", v / 1e6) }
        if v >= 1e3 { return String(format: "%.1fK", v / 1e3) }
        return "\(n)"
    }

    // MARK: - 货币格式化

    /// 传入原始美元金额,按当前货币设置输出("¥61.2" / "$8.50")
    func currencyStr(_ usd: Double) -> String {
        switch currency {
        case .usd:
            return usd >= 100 ? "$" + Self.groupedWhole(usd)
                : (usd >= 10 ? String(format: "$%.1f", usd) : String(format: "$%.2f", usd))
        case .cny:
            let v = usd * usdToCny
            return v >= 100 ? "¥" + Self.groupedWhole(v)
                : (v >= 10 ? String(format: "¥%.1f", v) : String(format: "¥%.2f", v))
        }
    }

    private static func groupedWhole(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US"))
            .grouping(.automatic).precision(.fractionLength(0)))
    }

    /// 紧凑版(菜单栏用):¥61 / $8.5
    func currencyCompact(_ usd: Double) -> String {
        switch currency {
        case .usd:
            return usd >= 100 ? String(format: "$%.0f", usd) : String(format: "$%.1f", usd)
        case .cny:
            let v = usd * usdToCny
            return v >= 100 ? String(format: "¥%.0f", v) : String(format: "¥%.1f", v)
        }
    }
}
