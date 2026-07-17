import SwiftUI
import AppKit
import UserNotifications

@main
struct MacPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var system = SystemMonitor()
    @StateObject private var usage = UsageStore()
    @StateObject private var cleanup = CleanupStore()
    @StateObject private var quota = QuotaStore()
    @StateObject private var skillStore = SkillManagerStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(system)
                .environmentObject(usage)
                .environmentObject(cleanup)
                .environmentObject(quota)
                .environmentObject(skillStore)
        } label: {
            MenuBarLabel(system: system, usage: usage, quota: quota)
                .onAppear {
                    system.start()
                    NotchDock.shared.start(system: system, usage: usage, quota: quota)
                    if UserDefaults.standard.bool(forKey: "macpulse.onboardingCompleted") {
                        usage.start()
                        quota.start()
                        VibeMoments.shared.start(system: system, usage: usage)
                    }
                }
                .modifier(AutoOpenDashboard())
        }
        .menuBarExtraStyle(.window)

        // 独立的 Token 监控台窗口(单实例);从弹窗「打开监控台」按钮开启
        Window("Token 监控台", id: "dashboard") {
            DashboardRoot()
                .environmentObject(usage)
                .environmentObject(system)
                .environmentObject(quota)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 660)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏应用:不占 Dock、不抢焦点
        NSApp.setActivationPolicy(.accessory)
        NotificationManager.shared.bootstrap()
        showInstallLocationWarningIfNeeded()

        // 调试:MACPULSE_NOTIF_TEST 时 8 秒后发一条测试通知,验证 授权→排程→送达→刘海 整链
        if ProcessInfo.processInfo.environment["MACPULSE_NOTIF_TEST"] != nil {
            let c = UNUserNotificationCenter.current()
            c.getNotificationSettings { s in NSLog("[notif-test] authStatus=\(s.authorizationStatus.rawValue)") }
            let content = UNMutableNotificationContent()
            content.title = "Codex · 5 小时额度已重置"
            content.body = "满血复活,可以继续了 🎉"
            content.sound = .default
            content.userInfo = ["tool": "codex", "kind": "fiveHour"]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 8, repeats: false)
            c.add(UNNotificationRequest(identifier: "notif-test", content: content, trigger: trigger)) { err in
                NSLog("[notif-test] add err=\(String(describing: err))")
                c.getPendingNotificationRequests { r in NSLog("[notif-test] pending=\(r.count)") }
            }
        }

        // 调试:MACPULSE_NOTCH_TEST 时启动几秒后弹一条刘海测试提醒
        if ProcessInfo.processInfo.environment["MACPULSE_NOTCH_TEST"] != nil {
            NSLog("[notch-test] armed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NSLog("[notch-test] firing flash; screens=\(NSScreen.screens.count) notch=\(String(describing: NSScreen.builtInNotch?.notchSize))")
                NotchController.shared.flash(
                    NotchAlert(icon: "checkmark.circle.fill",
                               title: "Claude · 5 小时额度已重置",
                               subtitle: "满血复活,可以继续了 🎉",
                               tint: .green),
                    duration: 30, sound: false)
            }
        }
    }

    private func showInstallLocationWarningIfNeeded() {
        guard Bundle.main.bundlePath.hasPrefix("/Volumes/") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "请先把 MacPulse 拖到“应用程序”"
            alert.informativeText = "当前正在磁盘镜像中运行，应用内更新无法可靠安装。请退出后把 MacPulse 拖入 Applications，再从那里启动。"
            alert.addButton(withTitle: "打开应用程序文件夹")
            alert.addButton(withTitle: "稍后")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
            }
        }
    }
}

/// 调试用:设环境变量 MACPULSE_AUTOOPEN 时启动数秒后自动打开监控台窗口(正常使用不受影响)
private struct AutoOpenDashboard: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear {
            guard ProcessInfo.processInfo.environment["MACPULSE_AUTOOPEN"] != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { openWindow(id: "dashboard") }
        }
    }
}
