import Foundation

/// 额度窗口类型
enum QuotaKind: String, Sendable {
    case fiveHour       // 5 小时滚动
    case weekly         // 每周
    var label: String { self == .fiveHour ? "5 小时额度" : "本周额度" }
    var shortLabel: String { self == .fiveHour ? "5小时" : "每周" }
}

/// 一个额度窗口的当前状态
struct QuotaWindow: Sendable, Identifiable {
    let tool: ToolKind
    let kind: QuotaKind
    let usedPercent: Double      // 0~100
    let resetsAt: Date           // 窗口重置的绝对时刻
    let asOf: Date               // 数据快照时间(Claude OAuth=请求时;Codex=会话时)

    var id: String { "\(tool.rawValue)-\(kind.rawValue)" }

    /// 距重置还剩多久(秒);已过则 0
    func remaining(now: Date) -> TimeInterval { max(0, resetsAt.timeIntervalSince(now)) }

    /// 快照之后窗口是否已经重置(resets_at 已过)——此时 usedPercent 已过时,应视为"满额可用"
    func hasReset(now: Date) -> Bool { resetsAt <= now }

    /// 给非技术用户看的"还能用多久":已重置=满额;否则剩余时间
    func headline(now: Date) -> String {
        if hasReset(now: now) { return "满额可用" }
        return "还能用 " + QuotaFormat.duration(remaining(now: now))
    }

    /// 有效已用百分比(已重置视为 0)
    func effectiveUsed(now: Date) -> Double { hasReset(now: now) ? 0 : usedPercent }
}

/// 一个工具(Claude/Codex)的额度汇总
struct ToolQuota: Sendable, Identifiable {
    let tool: ToolKind
    let plan: String?            // plus / pro / max…
    let windows: [QuotaWindow]
    let authoritative: Bool      // Claude OAuth / Codex rate_limits = 权威;推断 = false
    let asOf: Date               // 整体数据新鲜度

    var id: String { tool.rawValue }
    var fiveHour: QuotaWindow? { windows.first { $0.kind == .fiveHour } }
    var weekly: QuotaWindow? { windows.first { $0.kind == .weekly } }
}

enum QuotaFormat {
    /// 3660 秒 → "1h1m";86400+ → "1天2h";< 60s → "<1m"
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        if s < 60 { return "<1分钟" }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)天\(h)小时" }
        if h > 0 { return "\(h)小时\(m)分" }
        return "\(m)分钟"
    }

    /// 重置时刻 → 本地"07-07 01:00"
    static func resetClock(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; f.timeZone = .current
        return f.string(from: date)
    }
}
