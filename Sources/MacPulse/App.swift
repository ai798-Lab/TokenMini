import SwiftUI
import AppKit
import UserNotifications
import Darwin

@main
struct MacPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var system = SystemMonitor()
    @StateObject private var usage = UsageStore()
    @StateObject private var cleanup = CleanupStore()
    @StateObject private var processActions = ProcessActionStore()
    @StateObject private var quota = QuotaStore()
    @StateObject private var skillStore = SkillManagerStore()
    @StateObject private var leaderboard = LeaderboardStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(system)
                .environmentObject(usage)
                .environmentObject(cleanup)
                .environmentObject(processActions)
                .environmentObject(quota)
                .environmentObject(skillStore)
                .environmentObject(leaderboard)
        } label: {
            MenuBarLabel(system: system, usage: usage, quota: quota)
                .onAppear {
                    system.start()
                    leaderboard.start(usage: usage)
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
        Window("TokenMini · Token 监控台", id: "dashboard") {
            DashboardRoot()
                .environmentObject(usage)
                .environmentObject(system)
                .environmentObject(quota)
                .environmentObject(leaderboard)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 660)

        Window("TokenMini · 清理与内存管理", id: "maintenance") {
            MaintenanceView()
                .environmentObject(cleanup)
                .environmentObject(system)
                .environmentObject(processActions)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 700, height: 650)

        Window("社区排行", id: "leaderboard") {
            LeaderboardView()
                .environmentObject(leaderboard)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 620, height: 700)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let singleInstance = SingleInstanceGuard()
    private var duplicateLaunchObserver: NSObjectProtocol?
    private var duplicateGuardTimer: Timer?
    private var terminatingDuplicatePIDs: Set<pid_t> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard singleInstance.acquire() else {
            // 同一用户已经有一份 MacPulse 在运行。第二份必须在创建菜单栏与刘海浮层前退出，
            // 否则 /Applications 与工作区 dist 同时启动时会出现两个“灵动岛”。
            NSLog("[single-instance] another MacPulse is already running; terminating duplicate")
            NSApp.terminate(nil)
            return
        }
        terminateOtherInstances()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏应用:不占 Dock、不抢焦点
        NSApp.setActivationPolicy(.accessory)
        duplicateLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self?.terminateIfDuplicate(app)
        }
        let guardTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.terminateOtherInstances()
        }
        guardTimer.tolerance = 0.2
        RunLoop.main.add(guardTimer, forMode: .common)
        duplicateGuardTimer = guardTimer
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: Notification.Name("MacPulse.openMaintenance"), object: nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        duplicateGuardTimer?.invalidate()
        if let duplicateLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(duplicateLaunchObserver)
        }
    }

    /// 兼容电脑里尚未升级、还不知道互斥锁的旧副本：当前新版启动时清掉旧副本，
    /// 之后若旧副本又被登录项/用户启动，也会在它创建第二个刘海后立即终止。
    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .forEach(terminateIfDuplicate)
    }

    private func terminateIfDuplicate(_ app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier == Bundle.main.bundleIdentifier,
              !terminatingDuplicatePIDs.contains(app.processIdentifier) else { return }
        let pid = app.processIdentifier
        terminatingDuplicatePIDs.insert(pid)
        NSLog("[single-instance] terminating later duplicate pid=\(app.processIdentifier)")
        let accepted = app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if !accepted || !app.isTerminated { _ = app.forceTerminate() }
            self?.terminatingDuplicatePIDs.remove(pid)
        }
    }

    private func showInstallLocationWarningIfNeeded() {
        guard Bundle.main.bundlePath.hasPrefix("/Volumes/") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "请先把 TokenMini 拖到“应用程序”"
            alert.informativeText = "当前正在磁盘镜像中运行，应用内更新无法可靠安装。请退出后把 TokenMini 拖入 Applications，再从那里启动。"
            alert.addButton(withTitle: "打开应用程序文件夹")
            alert.addButton(withTitle: "稍后")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
            }
        }
    }

}

/// 进程级互斥锁:同一 macOS 用户只能有一个 MacPulse 实例。
/// 文件可以留在 /private/tmp;真正的锁由内核持有，进程退出后会自动释放。
private final class SingleInstanceGuard {
    private var descriptor: Int32 = -1

    func acquire() -> Bool {
        guard descriptor < 0 else { return true }
        let path = "/private/tmp/macpulse-\(getuid()).lock"
        let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            // 临时目录异常不应让 app 完全打不开；仅在明确拿不到锁时阻止重复实例。
            return true
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        descriptor = fd
        return true
    }

    deinit {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

/// 调试用:用环境变量自动打开指定窗口,便于离屏验收(正常使用不受影响)。
private struct AutoOpenDashboard: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: Notification.Name("MacPulse.openMaintenance"))) { _ in
            openWindow(id: "maintenance")
            NSApp.activate(ignoringOtherApps: true)
        }.onAppear {
            let environment = ProcessInfo.processInfo.environment
            if environment["MACPULSE_AUTOOPEN"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) { openWindow(id: "dashboard") }
            }
            if environment["MACPULSE_OPEN_LEADERBOARD"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { openWindow(id: "leaderboard") }
            }
        }
    }
}
