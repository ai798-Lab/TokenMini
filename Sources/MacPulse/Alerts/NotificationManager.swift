import Foundation
@preconcurrency import UserNotifications
import SwiftUI

enum CostAlertKind: String, Equatable, Sendable {
    case hourly
    case daily
}

/// 成本提醒的纯判断层。阈值 <= 0 视为未配置，便于测试且避免异常配置导致每次扫描都提醒。
enum CostAlertEvaluator {
    static func evaluate(hourlyUSD: Double, todayUSD: Double,
                         hourlyThresholdUSD: Double,
                         dailyThresholdUSD: Double) -> [CostAlertKind] {
        var result: [CostAlertKind] = []
        if hourlyThresholdUSD > 0, hourlyUSD >= hourlyThresholdUSD { result.append(.hourly) }
        if dailyThresholdUSD > 0, todayUSD >= dailyThresholdUSD { result.append(.daily) }
        return result
    }
}

/// 额度重置提醒:到点发系统通知;若 app 在运行,同时在刘海弹强提醒。
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private static let enabledKey = "macpulse.alertsEnabled"
    private static let costEnabledKey = "macpulse.costAlertsEnabled"
    private static let hourlyThresholdKey = "macpulse.hourlyCostThresholdUSD"
    private static let dailyThresholdKey = "macpulse.dailyCostThresholdUSD"
    private static let lastHourlyAlertKey = "macpulse.lastHourlyCostAlert"
    private static let lastDailyAlertKey = "macpulse.lastDailyCostAlert"
    @Published private(set) var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if !enabled { clearManaged(prefix: resetPrefix) }
        }
    }
    @Published private(set) var costAlertsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(costAlertsEnabled, forKey: Self.costEnabledKey)
            if !costAlertsEnabled { clearManaged(prefix: costPrefix) }
        }
    }
    @Published var hourlyThresholdUSD: Double {
        didSet { UserDefaults.standard.set(hourlyThresholdUSD, forKey: Self.hourlyThresholdKey) }
    }
    @Published var dailyThresholdUSD: Double {
        didSet { UserDefaults.standard.set(dailyThresholdUSD, forKey: Self.dailyThresholdKey) }
    }

    private let resetPrefix = "reset-"
    private let costPrefix = "cost-alert-"

    override init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: Self.enabledKey) // 默认关闭，用户主动开启时才申请系统权限
        costAlertsEnabled = d.bool(forKey: Self.costEnabledKey) // 默认关闭，避免升级后突然打扰
        hourlyThresholdUSD = d.object(forKey: Self.hourlyThresholdKey) == nil
            ? 20 : d.double(forKey: Self.hourlyThresholdKey)
        dailyThresholdUSD = d.object(forKey: Self.dailyThresholdKey) == nil
            ? 100 : d.double(forKey: Self.dailyThresholdKey)
        super.init()
    }

    func bootstrap() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .denied else { return }
            Task { @MainActor in
                self?.enabled = false
                self?.costAlertsEnabled = false
            }
        }
    }

    func setAlertsEnabled(_ requested: Bool) {
        setPermissionBackedFlag(requested) { [weak self] granted in self?.enabled = granted }
    }

    func setCostAlertsEnabled(_ requested: Bool) {
        setPermissionBackedFlag(requested) { [weak self] granted in self?.costAlertsEnabled = granted }
    }

    private func setPermissionBackedFlag(_ requested: Bool,
                                         assign: @escaping @MainActor (Bool) -> Void) {
        guard requested else { assign(false); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
            granted, _ in
            Task { @MainActor in assign(granted) }
        }
    }

    /// 为每个额度窗口的未来重置时刻排一条"已重置"通知(按 identifier 覆盖,重复排安全)
    func scheduleResetNotifications(_ quotas: [ToolQuota], now: Date = Date()) {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        var requests: [UNNotificationRequest] = []
        for q in quotas {
            for w in q.windows where w.resetsAt > now {
                let content = UNMutableNotificationContent()
                content.title = "\(q.tool.label) · \(w.kind.label)已重置"
                content.body = "满血复活,可以继续了 🎉"
                content.sound = .default
                content.interruptionLevel = .timeSensitive   // 无 entitlement 时自动降级为 .active,不崩
                content.userInfo = ["tool": q.tool.rawValue, "kind": w.kind.rawValue]
                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: w.resetsAt)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let req = UNNotificationRequest(identifier: resetPrefix + w.id, content: content, trigger: trigger)
                requests.append(req)
            }
        }
        let desired = Set(requests.map(\.identifier))
        center.getPendingNotificationRequests { [resetPrefix] pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(resetPrefix) && !desired.contains($0) }
            if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
            for request in requests { center.add(request) }
        }
    }

    /// 每小时/每天最多提醒一次；跨进程保存去重键，重启 app 也不会补弹同一周期。
    func evaluateCostAlerts(hourlyUSD: Double, todayUSD: Double,
                            topProject: String?, now: Date = Date()) {
        guard costAlertsEnabled else { return }
        let kinds = CostAlertEvaluator.evaluate(
            hourlyUSD: hourlyUSD, todayUSD: todayUSD,
            hourlyThresholdUSD: hourlyThresholdUSD,
            dailyThresholdUSD: dailyThresholdUSD)
        let cal = Calendar.current
        let hourBucket = Int(now.timeIntervalSince1970 / 3600)
        let dayBucket = cal.ordinality(of: .day, in: .era, for: now) ?? 0
        let d = UserDefaults.standard

        for kind in kinds {
            let bucket = kind == .hourly ? hourBucket : dayBucket
            let key = kind == .hourly ? Self.lastHourlyAlertKey : Self.lastDailyAlertKey
            guard d.integer(forKey: key) != bucket else { continue }
            d.set(bucket, forKey: key)
            sendCostAlert(kind, hourlyUSD: hourlyUSD, todayUSD: todayUSD,
                          topProject: topProject, bucket: bucket)
        }
    }

    private func sendCostAlert(_ kind: CostAlertKind, hourlyUSD: Double, todayUSD: Double,
                               topProject: String?, bucket: Int) {
        let settings = DisplaySettings.shared
        let amount = settings.currencyStr(kind == .hourly ? hourlyUSD : todayUSD)
        let scope = kind == .hourly ? "过去 1 小时" : "今天"
        let threshold = settings.currencyStr(kind == .hourly ? hourlyThresholdUSD : dailyThresholdUSD)
        let project = topProject.map { " · 主要来自 \($0)" } ?? ""

        let content = UNMutableNotificationContent()
        content.title = "AI 等价成本提醒 · \(scope) \(amount)"
        content.body = "已达到你设置的 \(threshold) 阈值\(project)"
        content.sound = .default
        content.interruptionLevel = .active
        let identifier = "\(costPrefix)\(kind.rawValue)-\(bucket)"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil))

        NotchController.shared.flash(
            NotchAlert(icon: "exclamationmark.triangle.fill",
                       title: "AI 等价成本 · \(scope) \(amount)",
                       subtitle: "达到 \(threshold) 提醒线\(project)",
                       tint: .orange),
            duration: 6, sound: true)
    }

    private func clearManaged(prefix: String) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let managed = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !managed.isEmpty { center.removePendingNotificationRequests(withIdentifiers: managed) }
        }
        center.getDeliveredNotifications { delivered in
            let managed = delivered.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) }
            if !managed.isEmpty { center.removeDeliveredNotifications(withIdentifiers: managed) }
        }
    }

    // 前台(菜单栏 agent 常驻)也展示横幅。刘海强提醒由 QuotaStore 直接触发,不在这里重复。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            completionHandler((self.enabled || self.costAlertsEnabled) ? [.banner, .sound, .list] : [])
        }
    }
}
