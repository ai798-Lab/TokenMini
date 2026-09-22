import AppKit
import SwiftUI
import Combine

/// 展开状态(控制器用鼠标监听驱动,视图观察)
@MainActor
final class NotchDockState: ObservableObject {
    @Published var expanded = false
    /// 鼠标在面板内的位置(面板本地坐标,左上原点;nil = 不在面板上)。
    /// 由 NotchDock 的全局监听喂——非激活浮层上 SwiftUI 的 hover/onContinuousHover 不可靠,
    /// 所以这儿不能用 `trackingMouse`。喂给轮廓光和跟随光斑。
    @Published var mouse: CGPoint?
    /// 内容实测高度(视图自己量了报上来)。面板高度按它走,不再靠猜。
    @Published var contentHeight: CGFloat = 0
}

/// 刘海常驻交互:平时**完全隐藏**(只有物理刘海),鼠标移到刘海处 → 从刘海**无缝长出**
/// 黑色下拉面板(上接刘海、下带圆角);鼠标移开自动收起。
/// 用全局鼠标位置监听驱动 hover,比 SwiftUI .onHover 在不激活浮层上更可靠。
@MainActor
final class NotchDock {
    static let shared = NotchDock()

    private var panel: NotchDockPanel?
    private var system: SystemMonitor?
    private var usage: UsageStore?
    private var quota: QuotaStore?
    private let state = NotchDockState()

    private var globalMon: Any?
    private var localMon: Any?
    private var collapseTask: DispatchWorkItem?
    /// 内容高度订阅(observeContentHeight 里建,只建一次)
    private var heightObs: AnyCancellable?

    private let enabledKey = "macpulse.notchDockEnabled"
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) == nil ? true : UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey); newValue ? show() : hide() }
    }

    private let panelWidth: CGFloat = 380

    /// 还没量到内容高度时的起手值(只影响首次展开的那一帧)。
    /// 别再把这里当"面板高度"来调:内容高度随主题、随额度窗口条数变,写死的数永远对不准——
    /// 高估就在底下空出一大块(这块反复调过 336→306 也没对准,用户还是一眼看出"间距特别大"),
    /// 低估则内容被裁。真正的高度由视图用 NotchContentHeight 量了报上来。
    private var estimatedHeight: CGFloat {
        switch DisplaySettings.shared.theme {
        case .classic: return 300
        case .hud, .prism: return 322
        case .led: return 306
        }
    }

    private var expandedSize: NSSize {
        NSSize(width: panelWidth,
               height: state.contentHeight > 1 ? state.contentHeight : estimatedHeight)
    }

    private func expandedFrame(height: CGFloat, screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.midX - panelWidth / 2,
               y: screen.frame.maxY - height,
               width: panelWidth, height: height)
    }

    func start(system: SystemMonitor, usage: UsageStore, quota: QuotaStore) {
        guard self.system == nil else { return }
        self.system = system; self.usage = usage; self.quota = quota
        if enabled { show() }
    }

    func show() {
        guard let screen = NSScreen.builtInNotch ?? NSScreen.main,
              let system, let usage, let quota else { return }
        if panel?.isVisible == true {
            installMonitors()
            return
        }
        let p = panel ?? NotchDockPanel()
        panel = p
        p.setFrame(frame(expanded: false, screen: screen), display: false, animate: false)

        let host = NSHostingView(rootView: NotchDockView(
            system: system, usage: usage, quota: quota, state: state,
            notchSize: screen.notchSize ?? NSSize(width: 180, height: 32)))
        host.frame = NSRect(origin: .zero, size: p.frame.size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        p.orderFrontRegardless()
        installMonitors()
        observeContentHeight()
    }

    /// 内容量出高度就即刻贴合面板。
    /// 注意用回调里的 h 现算,不要走 expandedSize:@Published 是 willSet 时机发的,
    /// 这会儿 state.contentHeight 还是旧值,拿它算会永远慢一拍。
    private func observeContentHeight() {
        guard heightObs == nil else { return }
        heightObs = state.$contentHeight
            .removeDuplicates()
            .sink { [weak self] h in
                guard let self, h > 1, self.state.expanded,
                      let screen = NSScreen.builtInNotch ?? NSScreen.main else { return }
                // 首次展开时这一下纠正会撞上展开动画(缩放+淡入),看不出来;
                // 之后 contentHeight 一直留着,每次展开都已经是量好的高度,不会二段跳。
                self.panel?.setFrame(self.expandedFrame(height: h, screen: screen),
                                     display: true, animate: false)
            }
    }

    func hide() {
        removeMonitors()
        state.mouse = nil        // 监听已摘,位置不会再更新——不清会把最后一帧的光斑留在原地
        panel?.orderOut(nil)
    }

    // MARK: 鼠标监听驱动 hover

    private func installMonitors() {
        guard globalMon == nil else { return }
        globalMon = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.mouseMoved() }
        }
        localMon = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in
            Task { @MainActor in self?.mouseMoved() }
            return e
        }
    }

    private func removeMonitors() {
        if let g = globalMon { NSEvent.removeMonitor(g); globalMon = nil }
        if let l = localMon { NSEvent.removeMonitor(l); localMon = nil }
    }

    private func mouseMoved() {
        guard panel != nil, let screen = NSScreen.builtInNotch ?? NSScreen.main else { return }
        let loc = NSEvent.mouseLocation                       // 屏幕坐标(左下原点)
        let hot = frame(expanded: state.expanded, screen: screen)
        // 喂光效:屏幕坐标(左下原点)→ 面板本地坐标(左上原点),SwiftUI 那边直接可用
        let inside = hot.contains(loc)
        let local = inside ? CGPoint(x: loc.x - hot.minX, y: hot.maxY - loc.y) : nil
        if state.mouse != local { state.mouse = local }
        if state.expanded {
            if hot.insetBy(dx: -6, dy: -6).contains(loc) { collapseTask?.cancel(); collapseTask = nil }
            else { scheduleCollapse() }
        } else if frame(expanded: false, screen: screen).contains(loc) {
            setExpanded(true, screen: screen)
        }
    }

    private func scheduleCollapse() {
        guard collapseTask == nil else { return }
        let t = DispatchWorkItem { [weak self] in
            guard let self, let screen = NSScreen.builtInNotch ?? NSScreen.main else { return }
            self.collapseTask = nil
            self.setExpanded(false, screen: screen)
        }
        collapseTask = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: t)
    }

    private func setExpanded(_ on: Bool, screen: NSScreen) {
        guard state.expanded != on else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel?.setFrame(frame(expanded: on, screen: screen), display: true, animate: !reduceMotion)
        if reduceMotion { state.expanded = on }
        else { withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { state.expanded = on } }
    }

    /// 收起态 = 只覆盖物理刘海(透明,做感应区);展开态 = 从屏幕顶沿下拉的黑色面板。
    private func frame(expanded: Bool, screen: NSScreen) -> NSRect {
        let notch = screen.notchSize ?? NSSize(width: 180, height: 32)
        if expanded {
            return expandedFrame(height: expandedSize.height, screen: screen)
        } else {
            // 只覆盖刘海一小圈做 hover 感应区(内容透明,平时看不见)
            let w = notch.width + 20, h = notch.height + 4
            return NSRect(x: screen.frame.midX - w / 2,
                          y: screen.frame.maxY - h, width: w, height: h)
        }
    }
}

/// 刘海面板:不 ignoresMouseEvents(视图内也可交互),不抢焦点。
final class NotchDockPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
