import SwiftUI
import AppKit

// MARK: - HUD 主题(FUI/电视包装风)
// 整套 UI 的视觉基调:深空底 + 示波青主色 + 等宽代号标注 + 切角面板 + 四角括号。
// 所有界面共用这里的色板/字体/容器,不要在各视图里散落硬编码颜色。

enum HUD {
    // 底色
    static let bg      = Color(red: 0.027, green: 0.039, blue: 0.063)   // 深空底 #070A10
    static let panel   = Color(red: 0.055, green: 0.078, blue: 0.118)   // 面板底
    static let panelHi = Color(red: 0.078, green: 0.110, blue: 0.161)   // hover 面板底

    // 信号色
    static let cyan    = Color(red: 0.32, green: 0.89, blue: 1.00)      // 主色:示波青
    static let green   = Color(red: 0.25, green: 0.98, blue: 0.60)
    static let amber   = Color(red: 1.00, green: 0.72, blue: 0.18)
    static let red     = Color(red: 1.00, green: 0.30, blue: 0.34)
    static let violet  = Color(red: 0.64, green: 0.56, blue: 1.00)
    static let pink    = Color(red: 1.00, green: 0.42, blue: 0.74)
    static let ice     = Color(red: 0.62, green: 0.80, blue: 1.00)
    static let mint    = Color(red: 0.45, green: 0.94, blue: 0.85)

    // 文字层级。对比度按最差情形 panelHi(hover 面板底)算:text 14.4:1 / dim 8.1:1 / faint 5.1:1。
    // 旧的 faint 只有 2.8:1,小字读不出来;调亮时保持原来的冷蓝灰色相,只提亮度。
    static let text    = Color(red: 0.87, green: 0.93, blue: 1.00)
    static let dim     = Color(red: 0.62, green: 0.71, blue: 0.82)
    static let faint   = Color(red: 0.47, green: 0.56, blue: 0.67)

    // 线
    static let hairline = cyan.opacity(0.16)
    static let gridline = Color.white.opacity(0.05)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// 负载语义色:低=青,中=琥珀,高=红(阈值与旧版红黄绿一致)
    static func load(_ ratio: Double, warn: Double = 0.75, bad: Double = 0.9) -> Color {
        ratio >= bad ? red : (ratio >= warn ? amber : cyan)
    }
    /// 余量语义色(额度类):绿→琥珀→红
    static func quota(_ used: Double) -> Color {
        used >= 0.85 ? red : (used >= 0.6 ? amber : green)
    }
}

// MARK: - 切角矩形(电视包装的标志性形状)

struct CutCorner: Shape {
    struct Corners: OptionSet {
        let rawValue: Int
        static let topLeft     = Corners(rawValue: 1)
        static let topRight    = Corners(rawValue: 2)
        static let bottomLeft  = Corners(rawValue: 4)
        static let bottomRight = Corners(rawValue: 8)
        static let all: Corners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        static let diagonal: Corners = [.topRight, .bottomLeft]
    }
    var cut: CGFloat = 7
    var corners: Corners = .diagonal

    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = min(cut, min(r.width, r.height) / 2)
        if corners.contains(.topLeft) {
            p.move(to: CGPoint(x: r.minX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.minX + c, y: r.minY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
        }
        if corners.contains(.topRight) {
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        } else {
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        }
        if corners.contains(.bottomRight) {
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        } else {
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
        if corners.contains(.bottomLeft) {
            p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        } else {
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - 四角括号(取景框 ticks)

struct CornerBrackets: Shape {
    var length: CGFloat = 7
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = min(length, min(r.width, r.height) / 3)
        p.move(to: CGPoint(x: r.minX, y: r.minY + l))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

// MARK: - HUD 面板容器(暗底 + 发丝线 + 四角括号;hover 时括号展开提亮)

struct HUDPanel<Content: View>: View {
    var padding: CGFloat = 10
    var accent: Color = HUD.cyan
    @ViewBuilder var content: () -> Content
    /// 鼠标位置一处监听、两处用光(轮廓光 + 光斑);非 nil 即 hover 态
    @State private var mouse: CGPoint?
    private var hover: Bool { mouse != nil }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Rectangle().fill(HUD.panel.opacity(hover ? 0.9 : 0.72))
                    Rectangle().strokeBorder(Color.white.opacity(hover ? 0.11 : 0.07), lineWidth: 1)
                    CornerBrackets(length: hover ? 9 : 6)
                        .stroke(accent.opacity(hover ? 1 : 0.65), lineWidth: 1)
                }
            }
            // 轮廓光跟着指针走(不自转):一直转会让整屏面板都在闪,喧宾夺主
            .overlay {
                SweepBorder(shape: Rectangle(), color: accent, lineWidth: 1, drive: .follow(mouse))
            }
            .mouseSpotlight(color: accent, at: mouse, radius: 110, intensity: 0.10, clip: Rectangle())
            .shadow(color: accent.opacity(hover ? 0.14 : 0), radius: 7)
            .animation(.easeOut(duration: 0.16), value: hover)
            .trackingMouse($mouse)
    }
}

// MARK: - 分区标头:▎中文名 CODE ──────── (trailing)

struct HUDSectionHeader: View {
    let cn: String
    let code: String
    var accent: Color = HUD.cyan
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(accent).frame(width: 2, height: 9)
            Text(cn)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HUD.text)
                .fixedSize()
            Text(code)
                .font(HUD.mono(8, .medium))
                .kerning(1.1)
                .foregroundStyle(HUD.faint)
                .lineLimit(1)
                .fixedSize()
            Rectangle().fill(HUD.gridline).frame(height: 1)
            if let trailing { trailing }
        }
    }
}

// MARK: - 分段 LED 油量条(广播味的等分格;首次出现时从 0 充能到位)

struct HUDGauge: View {
    var ratio: Double                 // 0~1
    var color: Color
    var height: CGFloat = 7
    var segments: Int = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var powered = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                Rectangle()
                    .fill(i < litCount ? color : Color.white.opacity(0.08))
                    .opacity(i == litCount - 1 ? 1 : (i < litCount ? 0.82 : 1))
            }
        }
        .frame(height: height)
        .shadow(color: color.opacity(ratio > 0.01 ? 0.35 : 0), radius: 3)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: litCount)
        .onAppear {
            if reduceMotion { powered = true }
            else { withAnimation(.spring(response: 0.7, dampingFraction: 0.88).delay(0.06)) { powered = true } }
        }
    }

    private var litCount: Int {
        let r = powered ? max(0, min(1, ratio)) : 0
        if r <= 0 { return 0 }
        return max(1, Int((r * Double(segments)).rounded()))
    }
}

// MARK: - 脉冲状态灯

struct HUDStatusDot: View {
    var color: Color = HUD.green
    var size: CGFloat = 6
    var pulses: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.85), radius: 3)
            .opacity(dimmed ? 0.3 : 1)
            .onAppear {
                guard pulses && !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

// MARK: - 小徽标 chip(计划名/估算等)

struct HUDChip: View {
    let text: String
    var color: Color = HUD.cyan
    var body: some View {
        Text(text)
            .font(HUD.mono(8, .bold))
            .kerning(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background {
                ZStack {
                    CutCorner(cut: 3).fill(color.opacity(0.12))
                    CutCorner(cut: 3).stroke(color.opacity(0.45), lineWidth: 1)
                }
            }
            .lineLimit(1)
    }
}

// MARK: - HUD 按钮(切角边框;filled = 实心主按钮;hover 辉光 + 按压缩放)

struct HUDButtonStyle: ButtonStyle {
    var accent: Color = HUD.cyan
    var filled: Bool = false
    var size: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, accent: accent, filled: filled, size: size)
    }

    private struct Chrome: View {
        let configuration: Configuration
        let accent: Color
        let filled: Bool
        let size: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(HUD.mono(size, .semibold))
                .foregroundStyle(filled ? HUD.bg : (hover ? accent : accent.opacity(0.92)))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background {
                    ZStack {
                        CutCorner(cut: 5).fill(filled ? accent : accent.opacity(hover ? 0.18 : 0.10))
                        if !filled {
                            CutCorner(cut: 5).stroke(accent.opacity(hover ? 0.95 : 0.5), lineWidth: 1)
                        }
                    }
                }
                .opacity((pressed ? 0.7 : 1) * (isEnabled ? 1 : 0.35))
                .shadow(color: accent.opacity(filled ? (hover ? 0.55 : 0.35) : (hover ? 0.3 : 0)),
                        radius: hover ? 7 : 5)
                .scaleEffect(pressed && !reduceMotion ? 0.95 : 1)
                .animation(.easeOut(duration: 0.12), value: hover)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
                .onHover { hover = isEnabled && $0 }
        }
    }
}

// MARK: - 列表行悬停高亮(微交互)

private struct HUDHoverHighlight: ViewModifier {
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .background(hover ? Color.white.opacity(0.05) : .clear)
            .overlay(alignment: .leading) {
                if hover { Rectangle().fill(HUD.cyan.opacity(0.8)).frame(width: 1.5) }
            }
            .padding(.horizontal, -4)
            .animation(.easeOut(duration: 0.12), value: hover)
            .onHover { hover = $0 }
    }
}

extension View {
    /// HUD 列表行:悬停时淡淡打亮 + 左缘一根青色指示线
    func hudRowHover() -> some View { modifier(HUDHoverHighlight()) }
}

// MARK: - 毛玻璃(behindWindow:模糊窗口后面的桌面/内容)

struct HUDBlurView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

// MARK: - 弹窗外框整形(HUD 时把系统圆角 material 遮罩换成切角;经典时还原)
// MenuBarExtra(.window) 的圆角来自窗口里 NSVisualEffectView 的 maskImage,
// 直接替换 maskImage 既保留系统毛玻璃,又让整个窗体变成切角外形。

struct HUDWindowShaper: NSViewRepresentable {
    var active: Bool
    var cut: CGFloat = 14

    final class Coordinator {
        var recorded = Set<ObjectIdentifier>()
        var originals: [ObjectIdentifier: NSImage] = [:]
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ marker: NSView, context: Context) {
        let coord = context.coordinator
        let active = self.active
        let cut = self.cut
        DispatchQueue.main.async {
            guard let window = marker.window, let content = window.contentView else { return }
            var effects: [NSVisualEffectView] = []
            func walk(_ v: NSView) {
                if let e = v as? NSVisualEffectView { effects.append(e) }
                v.subviews.forEach(walk)
            }
            walk(content)
            for e in effects {
                let key = ObjectIdentifier(e)
                if !coord.recorded.contains(key) {
                    coord.recorded.insert(key)
                    if let m = e.maskImage { coord.originals[key] = m }
                }
                e.maskImage = active ? Self.cutMask(cut: cut) : coord.originals[key]
            }
            window.invalidateShadow()
        }
    }

    /// 顶部方角、底部双切角的九宫格拉伸遮罩(AppKit 坐标 minY 在底)
    static func cutMask(cut: CGFloat) -> NSImage {
        let side = cut * 2 + 2
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: rect.minX, y: rect.maxY))
            p.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            p.line(to: NSPoint(x: rect.maxX, y: rect.minY + cut))
            p.line(to: NSPoint(x: rect.maxX - cut, y: rect.minY))
            p.line(to: NSPoint(x: rect.minX + cut, y: rect.minY))
            p.line(to: NSPoint(x: rect.minX, y: rect.minY + cut))
            p.close()
            NSColor.black.setFill()
            p.fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: cut + 1, left: cut + 1, bottom: cut + 1, right: cut + 1)
        img.resizingMode = .stretch
        return img
    }
}

// MARK: - 网格背景(监控台用,极淡)

struct HUDGridBackground: View {
    var spacing: CGFloat = 26
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            ctx.stroke(path, with: .color(.white.opacity(0.028)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - HUD 滚动容器(隐藏系统滚动条,右缘画细线游标)

private struct HUDScrollMetrics: Equatable {
    var contentH: CGFloat = 0
    var offset: CGFloat = 0
}
private struct HUDScrollMetricsKey: PreferenceKey {
    static var defaultValue = HUDScrollMetrics()
    static func reduce(value: inout HUDScrollMetrics, nextValue: () -> HUDScrollMetrics) {
        value = nextValue()
    }
}

/// 系统开「始终显示滚动条」时,SwiftUI 的 scrollIndicators(.never) 压不住
/// NSScrollView 的常驻 scroller——从内容里向上找到宿主 NSScrollView 直接摘掉。
private struct HUDScrollerKiller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { Self.strip(from: v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        // 内容每次刷新都会走到这里,SwiftUI 若把 scroller 加回来也会被再次摘掉
        DispatchQueue.main.async { Self.strip(from: nsView) }
    }
    private static func strip(from view: NSView) {
        var v: NSView? = view.superview
        while let cur = v, !(cur is NSScrollView) { v = cur.superview }
        guard let scroll = v as? NSScrollView else { return }
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScroller?.alphaValue = 0
        scroll.horizontalScroller?.alphaValue = 0
    }
}

struct HUDScrollView<Content: View>: View {
    var accent: Color = HUD.cyan
    @ViewBuilder var content: () -> Content

    @State private var metrics = HUDScrollMetrics()
    @State private var viewportH: CGFloat = 0

    var body: some View {
        ScrollView {
            content()
                .background {
                    GeometryReader { geo in
                        let f = geo.frame(in: .named("hud.scroll"))
                        Color.clear.preference(key: HUDScrollMetricsKey.self,
                                               value: HUDScrollMetrics(contentH: f.height, offset: -f.minY))
                    }
                }
                .background { HUDScrollerKiller() }
        }
        .scrollIndicators(.never)
        .coordinateSpace(name: "hud.scroll")
        .onPreferenceChange(HUDScrollMetricsKey.self) { metrics = $0 }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewportH = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in viewportH = h }
            }
        }
        .overlay(alignment: .topTrailing) { indicator }
    }

    /// 细线游标:暗轨 + 发光段,位置/长度按滚动进度映射
    @ViewBuilder
    private var indicator: some View {
        if viewportH > 0, metrics.contentH > viewportH + 1 {
            let frac = viewportH / metrics.contentH
            let thumbH = max(24, viewportH * frac)
            let maxOff = metrics.contentH - viewportH
            let progress = maxOff > 0 ? min(1, max(0, metrics.offset / maxOff)) : 0
            ZStack(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.05)).frame(width: 2)
                Rectangle().fill(accent.opacity(0.6))
                    .frame(width: 2, height: thumbH)
                    .shadow(color: accent.opacity(0.5), radius: 2)
                    .offset(y: progress * (viewportH - thumbH))
            }
            .padding(.trailing, 2)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 实时时钟(HUD 顶栏那种 HH:MM:SS 读数)

struct HUDClock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Self.fmt.string(from: ctx.date))
                .font(HUD.mono(9, .medium))
                .kerning(0.8)
                .foregroundStyle(HUD.dim)
        }
    }
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
