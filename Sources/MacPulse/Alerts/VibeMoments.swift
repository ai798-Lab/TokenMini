import Foundation
import SwiftUI

/// Vibe 时刻:给 vibe coding 加一点仪式感 / 庆祝 / 关怀,都用刘海强提醒呈现。
/// - 开工大吉:每天第一次检测到 AI 活动
/// - 满血复活:额度重置(由 QuotaStore.detectResets 触发,这里不重复)
/// - 喝口水:持续写了一阵子的关怀提醒
/// - 电脑体温:电脑进入过热/吃紧的关怀提醒
/// 全部受"额度重置提醒"总开关约束;各自有防打扰节流。
@MainActor
final class VibeMoments {
    static let shared = VibeMoments()

    private var system: SystemMonitor?
    private var usage: UsageStore?
    private var timer: Timer?
    private let d = UserDefaults.standard

    private let kGreetDay = "macpulse.moment.greetDay"
    private let kBreak = "macpulse.moment.lastBreak"
    private let kHealth = "macpulse.moment.lastHealth"
    private let breakInterval: TimeInterval = 100 * 60   // 关怀提醒最短间隔
    private let healthInterval: TimeInterval = 30 * 60

    func start(system: SystemMonitor, usage: UsageStore) {
        guard timer == nil else { return }
        self.system = system; self.usage = usage
        if d.object(forKey: kBreak) == nil { d.set(Date().timeIntervalSince1970, forKey: kBreak) } // 启动不立刻催
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        t.tolerance = 15
        RunLoop.main.add(t, forMode: .common)
        timer = t
        check()
    }

    private var alertsOn: Bool { NotificationManager.shared.enabled }

    private func check() {
        guard alertsOn, let usage, let system else { return }
        let now = Date()

        // 开工大吉:今天第一次有 AI 活动
        let today = Self.dayString(now)
        if d.string(forKey: kGreetDay) != today, usage.today.eventCount > 0 {
            d.set(today, forKey: kGreetDay)
            NotchController.shared.flash(
                NotchAlert(icon: "cup.and.saucer.fill", title: "开工大吉 ☕",
                           subtitle: "今天也顺顺利利,冲!", tint: .orange),
                duration: 5)
        }

        // 喝口水:近 1 小时还在花钱(在写),且距上次关怀 > 间隔
        if usage.burnRatePerHourUSD > 0 {
            let last = d.double(forKey: kBreak)
            if now.timeIntervalSince1970 - last > breakInterval {
                d.set(now.timeIntervalSince1970, forKey: kBreak)
                NotchController.shared.flash(
                    NotchAlert(icon: "figure.walk.motion", title: "喝口水?🥤",
                               subtitle: "连着写有一会儿了,歇 5 分钟更清醒", tint: .teal),
                    duration: 6)
            }
        }

        // 电脑体温:进入过热/吃紧(critical),距上次 > 间隔
        let h = ComputerHealth.evaluate(system)
        if h.level == .critical {
            let last = d.double(forKey: kHealth)
            if now.timeIntervalSince1970 - last > healthInterval {
                d.set(now.timeIntervalSince1970, forKey: kHealth)
                NotchController.shared.flash(
                    NotchAlert(icon: "thermometer.high", title: h.title,
                               subtitle: h.detail + " · 给它喘口气", tint: .red),
                    duration: 6, sound: true)
            }
        }
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: date)
    }
}
