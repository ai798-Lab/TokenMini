import AppKit
import SwiftUI

@MainActor
final class ProductAnalytics: ObservableObject {
    static let shared = ProductAnalytics()
    @Published private(set) var enabled = false
    @Published private(set) var status = "产品统计默认关闭"
    private let queue: AnalyticsOutbox
    private let endpoint: URL?
    private let clientID: String
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var inputMonitor: Any?
    private var clock = AnalyticsClock()
    private var duration = AnalyticsDuration.zero
    private var suspensions: Set<String> = []
    private var suspended: Bool { !suspensions.isEmpty }
    private var lastInput = ProcessInfo.processInfo.systemUptime
    private var epoch = 0
    private var ticks = 0
    private var windows: [ObjectIdentifier: Surface] = [:]
    private struct Surface {
        weak var window: NSWindow?
        let event: ProductEvent
        var visible = false
    }
    var configured: Bool { endpoint != nil && !clientID.isEmpty }
    var destination: String { endpoint?.host ?? "尚未配置统计服务器" }

    private init() {
        let bundle = Bundle.main
        let env = ProcessInfo.processInfo.environment
        // Runtime overrides are restricted to loopback for local acceptance.
        let bundleURL = (bundle.object(forInfoDictionaryKey: "TokenMiniAnalyticsURL") as? String).flatMap(URL.init(string:))
        let testURL = env["TOKENMINI_ANALYTICS_TEST_URL"].flatMap(URL.init(string:)) ?? ((bundle.bundleIdentifier?.hasSuffix(".analytics-test") ?? false) ? bundleURL : nil)
        let local = testURL.map { ["localhost", "127.0.0.1", "::1"].contains($0.host ?? "") } ?? false
        let candidate = local ? testURL : bundleURL
        endpoint = candidate.flatMap { ($0.scheme == "https" || local) && $0.user == nil && $0.password == nil ? $0 : nil }
        clientID = (local ? env["TOKENMINI_ANALYTICS_TEST_CLIENT_ID"] : nil) ?? bundle.object(forInfoDictionaryKey: "TokenMiniAnalyticsClientID") as? String ?? ""
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cohort = UserDefaults.standard.bool(forKey: "macpulse.onboardingCompleted") ? "upgrade" : "unknown"
        queue = AnalyticsOutbox(file: base.appendingPathComponent(local ? "TokenMini/analytics-test/outbox.json" : "TokenMini/analytics/outbox.json"), cohort: cohort)
        enabled = queue.enabled && UserDefaults.standard.bool(forKey: consentKey)
        if !enabled { queue.setEnabled(false) }
        status = enabled ? "等待发送统计" : "产品统计默认关闭"
    }

    private var consentKey: String { endpoint?.scheme == "http" ? "tokenmini.analytics.testConsent.v1" : "tokenmini.analytics.consent.v1" }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        if value {
            guard configured else { status = "尚未配置统计服务器"; return }
            let alert = NSAlert()
            alert.messageText = "帮助改进 TokenMini？"
            alert.informativeText = "开启后向 \(destination) 发送随机安装标识、版本、面板打开次数和使用时长，用于活跃与留存分析。不会发送提示词、对话、项目名、文件路径、API Key 或用量明细。可随时关闭；关闭将清除待发送事件，已接收的数据不会自动删除。"
            alert.addButton(withTitle: "同意并开启")
            alert.addButton(withTitle: "暂不开启")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        epoch += 1
        task?.cancel(); task = nil
        UserDefaults.standard.set(value, forKey: consentKey)
        enabled = value
        queue.setEnabled(value)
        duration = .zero; clock.reset()
        status = value ? "已开启，等待发送" : "已关闭，待发送事件已清除"
        if queue.storageFailed { status = "本地统计存储失败；请保持关闭并重试" }
        if value { queue.record(.appStart); flush() }
    }

    func start() {
        guard timer == nil else { return }
        if enabled { queue.record(.appStart) }
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel, .mouseMoved]) { [weak self] event in
            self?.lastInput = ProcessInfo.processInfo.systemUptime
            return event // Never inspect or retain key codes, characters or event contents.
        }
        let center = NSWorkspace.shared.notificationCenter
        let pairs: [(String, Notification.Name, Notification.Name)] = [
            ("sleep", NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification),
            ("session", NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification),
            ("display", NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification)
        ]
        for (reason, pause, resume) in pairs {
            for (name, value) in [(pause, true), (resume, false)] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.pause(reason: reason, value: value) }
                })
            }
        }
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause(reason: "lock", value: value) }
            })
        }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        flush()
    }

    func register(_ window: NSWindow, event: ProductEvent) {
        let id = ObjectIdentifier(window)
        if windows[id] == nil { windows[id] = Surface(window: window, event: event) }
    }

    private func pause(reason: String, value: Bool) {
        persistDuration()
        if value { suspensions.insert(reason) } else { suspensions.remove(reason) }
        clock.reset()
    }

    private func sample() {
        guard enabled else { clock.reset(); return }
        var visible = false
        for id in Array(windows.keys) {
            guard var surface = windows[id], let window = surface.window else { windows.removeValue(forKey: id); continue }
            let showing = window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible) && !suspended
            if showing && !surface.visible { queue.record(surface.event); lastInput = ProcessInfo.processInfo.systemUptime }
            surface.visible = showing; windows[id] = surface
            visible = visible || showing
        }
        let uptime = ProcessInfo.processInfo.systemUptime
        let elapsed = clock.sample(uptime: uptime, running: !suspended,
            interacting: visible && NSApp.isActive && uptime - lastInput < 60)
        duration.runtime += elapsed.runtime
        duration.interaction += elapsed.interaction
        ticks += 1
        if ticks % 6 == 0 { persistDuration(); flush() }
    }

    private func persistDuration() {
        if enabled && duration.runtime > 0 { queue.record(.engagement, runtime: duration.runtime, interaction: duration.interaction) }
        duration = .zero
    }

    func stop() {
        persistDuration()
        timer?.invalidate(); timer = nil
        task?.cancel(); task = nil
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        lockObservers = []
    }

    private func flush() {
        guard enabled, configured, let endpoint, task == nil else { return }
        let generation = epoch
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.epoch == generation { self.task = nil } }
            // Sequential, bounded drain. The original ID and timestamp survive every retry.
            for _ in 0..<50 {
                guard self.enabled, self.epoch == generation, !Task.isCancelled,
                      let event = self.queue.events.first else { return }
                do {
                    var request = URLRequest(url: endpoint.appendingPathComponent("track"))
                    request.httpMethod = "POST"; request.timeoutInterval = 10
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(self.clientID, forHTTPHeaderField: "openpanel-client-id")
                    request.setValue("tokenmini", forHTTPHeaderField: "openpanel-sdk-name")
                    request.httpBody = try event.openPanelBody()
                    let (_, response) = try await URLSession.shared.data(for: request)
                    guard self.enabled, self.epoch == generation, !Task.isCancelled else { return }
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        self.status = "服务器未接收，稍后重试"; return
                    }
                    self.queue.acknowledge(event.id)
                    self.status = "已连接 · 待发送 \(self.queue.events.count) 条"
                } catch {
                    if self.enabled && self.epoch == generation { self.status = "暂时离线，事件留在本机等待补传" }
                    return
                }
            }
        }
    }
}

private struct AnalyticsWindowReader: NSViewRepresentable {
    let event: ProductEvent
    final class Reader: NSView {
        var event: ProductEvent = .menuViewed
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { ProductAnalytics.shared.register(window, event: event) }
        }
    }
    func makeNSView(context: Context) -> Reader { let view = Reader(); view.event = event; return view }
    func updateNSView(_ nsView: Reader, context: Context) { nsView.event = event }
}

extension View {
    func analyticsSurface(_ event: ProductEvent) -> some View {
        background(AnalyticsWindowReader(event: event).frame(width: 0, height: 0))
    }
}

struct ProductAnalyticsSettings: View {
    @ObservedObject private var analytics = ProductAnalytics.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle("帮助改进 TokenMini（可选）", isOn: Binding(get: { analytics.enabled }, set: { analytics.setEnabled($0) }))
                .disabled(!analytics.configured && !analytics.enabled)
            Text("仅发送随机标识、版本、面板打开次数与使用时长。不发送对话、项目或用量明细。")
            Text(analytics.configured ? analytics.status : "统计服务尚未配置，本版本不会发送产品统计。")
                .foregroundStyle(.secondary)
        }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
    }
}
