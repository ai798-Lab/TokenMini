import Foundation
import Combine

/// 额度中心:聚合 Claude(OAuth 端点,权威、实时)与 Codex(rollout 文件,截至上次会话)。
/// Codex 随文件读取(快),Claude 走网络(低频)。
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var quotas: [ToolQuota] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var claudeAccessEnabled: Bool

    /// 供预览/离屏渲染注入现成数据
    func injectForPreview(_ q: [ToolQuota]) { quotas = q; lastRefresh = Date() }

    static let codexInterval: TimeInterval = 90    // Codex 读文件,便宜
    static let claudeInterval: TimeInterval = 300  // Claude 走网络,5 分钟一次防 429

    private let codexReader = CodexQuotaReader()
    private let claudeReader = ClaudeQuotaReader()
    private let queue = DispatchQueue(label: "macpulse.quota", qos: .utility)
    private var codexTimer: Timer?
    private var claudeTimer: Timer?

    private var claudeQuota: ToolQuota?
    private var codexQuota: ToolQuota?
    private var seenResets: [String: Date] = [:]   // 窗口 → 上次见到的 resetsAt,用于探测重置
    private var warnedCycles: Set<String> = []     // 本轮已提醒过"快用完"的窗口周期,防重复

    private static let claudeAccessKey = "macpulse.claudeQuotaAccessEnabled"

    init() {
        claudeAccessEnabled = UserDefaults.standard.bool(forKey: Self.claudeAccessKey)
    }

    func start() {
        guard codexTimer == nil else { return }
        refreshCodex()
        if claudeAccessEnabled { refreshClaude() }
        let ct = Timer(timeInterval: Self.codexInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshCodex() }
        }
        let clt = Timer(timeInterval: Self.claudeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshClaude() }
        }
        ct.tolerance = 15; clt.tolerance = 30
        RunLoop.main.add(ct, forMode: .common)
        RunLoop.main.add(clt, forMode: .common)
        codexTimer = ct; claudeTimer = clt
    }

    func stop() {
        codexTimer?.invalidate(); codexTimer = nil
        claudeTimer?.invalidate(); claudeTimer = nil
    }

    /// Claude 额度依赖用户已有的 Claude Code 凭证与实验性端点，必须由用户主动开启。
    func setClaudeAccessEnabled(_ enabled: Bool) {
        guard claudeAccessEnabled != enabled else { return }
        claudeAccessEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.claudeAccessKey)
        if enabled {
            refreshClaude()
        } else {
            claudeQuota = nil
            publish()
        }
    }

    private func refreshCodex() {
        let reader = codexReader
        queue.async { [weak self] in
            let q = reader.read()
            Task { @MainActor in self?.codexQuota = q; self?.publish() }
        }
    }

    private func refreshClaude() {
        guard claudeAccessEnabled else { return }
        let reader = claudeReader
        Task { [weak self] in
            let q = await reader.fetch()
            await MainActor.run { self?.claudeQuota = q; self?.publish() }
        }
    }

    private func publish() {
        quotas = [claudeQuota, codexQuota].compactMap { $0 }
        lastRefresh = Date()
        detectResets(quotas)                                    // 直接触发刘海强提醒(不依赖通知权限)
        detectWarnings(quotas)                                  // 快用完:短暂弹一下,不持久挂条
        NotificationManager.shared.scheduleResetNotifications(quotas)  // 系统通知:尽力而为的第二通道
    }

    /// 额度快用完(5 小时额度 ≥ 85%)时,在刘海"短暂弹一下"提醒;每个额度周期只弹一次。
    private func detectWarnings(_ quotas: [ToolQuota]) {
        guard NotificationManager.shared.enabled else { return }
        let now = Date()
        var current = Set<String>()
        for q in quotas {
            for w in q.windows where w.kind == .fiveHour {
                let cycle = "\(w.id)@\(Int(w.resetsAt.timeIntervalSince1970))"
                current.insert(cycle)
                if !w.hasReset(now: now), w.usedPercent >= 85, !warnedCycles.contains(cycle) {
                    warnedCycles.insert(cycle)
                    NotchController.shared.flash(
                        NotchAlert(icon: "exclamationmark.triangle.fill",
                                   title: "\(q.tool.label) · 5 小时额度快用完",
                                   subtitle: "还剩约 \(QuotaFormat.duration(w.remaining(now: now))),悠着点写",
                                   tint: .orange),
                        duration: 6, sound: true)
                }
            }
        }
        warnedCycles.formIntersection(current)   // 清掉已过期周期,下个周期可再提醒
    }

    /// 探测重置:某窗口的 resetsAt 明显前移 = 上一个窗口已经重置 → 弹刘海强提醒。
    /// 首次见到只建基线不弹,避免启动时补弹一堆历史。
    private func detectResets(_ quotas: [ToolQuota]) {
        let alertsOn = NotificationManager.shared.enabled
        for q in quotas {
            for w in q.windows {
                if alertsOn, let prev = seenResets[w.id], w.resetsAt > prev.addingTimeInterval(120) {
                    NotchController.shared.flash(
                        NotchAlert(icon: "checkmark.circle.fill",
                                   title: "\(q.tool.label) · \(w.kind.label)已重置",
                                   subtitle: "满血复活,可以继续了 🎉",
                                   tint: .green),
                        duration: 7, sound: true)
                }
                seenResets[w.id] = w.resetsAt
            }
        }
    }

    /// 最紧张的窗口(有效已用最高),用于菜单栏/强提醒
    func mostConstrained(now: Date) -> QuotaWindow? {
        quotas.flatMap { $0.windows }.max { $0.effectiveUsed(now: now) < $1.effectiveUsed(now: now) }
    }
}
