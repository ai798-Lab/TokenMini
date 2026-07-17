import AppKit
import SwiftUI

// MARK: - 刘海检测(macOS 12+ 公开 API)

extension NSScreen {
    /// 是否有刘海
    var hasNotch: Bool {
        auxiliaryTopLeftArea?.width != nil && auxiliaryTopRightArea?.width != nil
    }
    /// 刘海宽高(无刘海返回 nil)
    var notchSize: NSSize? {
        guard let l = auxiliaryTopLeftArea?.width, let r = auxiliaryTopRightArea?.width else { return nil }
        return NSSize(width: frame.width - l - r, height: safeAreaInsets.top)
    }
    /// 内建刘海屏(优先当前主屏)
    static var builtInNotch: NSScreen? {
        NSScreen.screens.first { $0.hasNotch } ?? NSScreen.main
    }
}

// MARK: - 承载 HUD 的透明浮层(不拦截点击,压过菜单栏,跟随所有 Space)

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .screenSaver                       // 压过菜单栏/Dock
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true                  // 强提醒只展示,不拦点击
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - 强提醒内容模型

struct NotchAlert: Sendable {
    var icon: String
    var title: String
    var subtitle: String
    var tint: Color
    /// 有值则显示倒计时/进度环(0~1),否则显示图标
    var progress: Double? = nil
}

// MARK: - 刘海强提醒控制器

@MainActor
final class NotchController {
    static let shared = NotchController()
    private var panel: NotchPanel?
    private var gen = 0

    /// 在刘海处闪一条强提醒,duration 秒后自动收起(内容自带进/退场动画);
    /// 无刘海机型降级为顶部中央横幅。
    func flash(_ alert: NotchAlert, duration: TimeInterval = 6, sound: Bool = false) {
        let screen = NSScreen.builtInNotch ?? NSScreen.main
        guard let screen else { return }

        let width: CGFloat = 380
        let height: CGFloat = 140
        let frame = NSRect(x: screen.frame.midX - width / 2,
                           y: screen.frame.maxY - height,
                           width: width, height: height)

        let p = panel ?? NotchPanel()
        panel = p
        p.setFrame(frame, display: false)

        gen &+= 1
        let myGen = gen
        let host = NSHostingView(rootView: NotchAlertView(
            alert: alert,
            duration: duration,
            topInset: screen.safeAreaInsets.top,
            notchWidth: screen.notchSize?.width,
            onFinished: { [weak self] in
                guard let self, self.gen == myGen else { return }  // 已被新提醒取代则不关
                self.panel?.orderOut(nil)
            }))
        host.frame = NSRect(origin: .zero, size: frame.size)
        p.contentView = host
        p.orderFrontRegardless()

        if sound { NSSound(named: "Submarine")?.play() }
    }
}
