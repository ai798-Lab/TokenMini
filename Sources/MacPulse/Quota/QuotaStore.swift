import Foundation
import Combine

/// 额度重置的纯状态机:只有旧窗口确实到达边界后,才把更晚的 resetsAt 视为新周期。
/// Codex 多会话快照可能乱序,且滚动额度的 resetsAt 会在未重置时向后漂移;两者都不是重置事件。
struct QuotaResetDetector {
    private var latest: [String: QuotaWindow] = [:]
    private let minimumCycleShift: TimeInterval = 120
    private let boundaryTolerance: TimeInterval = 120

    mutating func observe(_ quotas: [ToolQuota], now: Date) -> [QuotaWindow] {
        var resets: [QuotaWindow] = []
        for window in quotas.flatMap(\.windows) {
            guard let previous = latest[window.id] else {
                latest[window.id] = window
                continue
            }

            // 不让其他会话中更旧的事件把检测基线拉回去。
            guard window.asOf >= previous.asOf else { continue }

            let shift = window.resetsAt.timeIntervalSince(previous.resetsAt)
            if shift > minimumCycleShift {
                // 旧周期还有很久才到期却出现新的 resetsAt,是漂移/异常快照。
                // 忽略它且不污染基线,避免形成“旧→新→旧→新”的反复提醒。
                guard now >= previous.resetsAt.addingTimeInterval(-boundaryTolerance) else { continue }
                if window.resetsAt > now { resets.append(window) }
            }

            // 新事件的向前校正可以接受,但不会触发提醒。
            latest[window.id] = window
        }
        return resets
    }
}

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
    private var resetDetector = QuotaResetDetector()
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
            refreshClaude(accessMode: .userInitiated)
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

    private func refreshClaude(accessMode: ClaudeKeychainAccessMode = .background) {
        guard claudeAccessEnabled else { return }
        let reader = claudeReader
        Task { [weak self] in
            let q = await reader.fetch(accessMode: accessMode)
            await MainActor.run {
                guard let self, self.claudeAccessEnabled else { return }
                self.claudeQuota = q
                self.publish()
            }
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
                        NotchAlert(icon: "eye.fill",
                                   title: "快到边啦，我帮你盯着",
                                   subtitle: "\(q.tool.label) 还剩约 \(QuotaFormat.duration(w.remaining(now: now)))，先写最重要的",
                                   tint: .orange),
                        duration: 6, sound: true)
                }
            }
        }
        warnedCycles.formIntersection(current)   // 清掉已过期周期,下个周期可再提醒
    }

    /// 探测重置:旧窗口已到期 + resetsAt 进入新周期 → 弹刘海强提醒。
    /// 首次见到只建基线不弹,避免启动时补弹一堆历史。
    private func detectResets(_ quotas: [ToolQuota]) {
        let resetWindows = resetDetector.observe(quotas, now: Date())
        guard NotificationManager.shared.enabled else { return }
        for w in resetWindows {
            NotchController.shared.flash(
                NotchAlert(icon: "checkmark.circle.fill",
                           title: "满血回来啦，可以继续了 🎉",
                           subtitle: "\(w.tool.label) · \(w.kind.label)已经恢复",
                           tint: .green),
                duration: 7, sound: true)
        }
    }

    /// 最紧张的窗口(有效已用最高),用于菜单栏/强提醒
    func mostConstrained(now: Date) -> QuotaWindow? {
        quotas.flatMap { $0.windows }.max { $0.effectiveUsed(now: now) < $1.effectiveUsed(now: now) }
    }
}
