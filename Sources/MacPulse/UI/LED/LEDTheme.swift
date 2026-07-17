import SwiftUI
import AppKit

// MARK: - LED 主题(复古健身器材仪表风)
// 参考:跑步机/健身房 LED 显示屏——近黑底、LED 点阵发光面板、七段数码管读数、
// 一类功能一种 LED 色(红=系统/负载,琥珀=金钱/能量,绿=健康/余量,黄=CTA),
// 控件是 iOS 味的圆角胶囊。所有 LED 界面共用这里的色板/组件。

enum LED {
    static let bg     = Color(red: 0.051, green: 0.051, blue: 0.055)   // 近黑
    static let chrome = Color(red: 0.11, green: 0.11, blue: 0.12)      // 深灰胶囊/控件底
    static let red    = Color(red: 1.00, green: 0.25, blue: 0.21)      // LED 红
    static let amber  = Color(red: 1.00, green: 0.62, blue: 0.04)      // LED 琥珀
    static let yellow = Color(red: 1.00, green: 0.76, blue: 0.03)      // CTA 黄
    static let green  = Color(red: 0.38, green: 0.95, blue: 0.35)      // LED 绿
    // 文字层级。面板底不是纯黑——LEDPanel 中心那层琥珀底光(hover 时 0.30)会把底色抬到 L≈0.042,
    // 灰字的对比度要按**面板中心 hover**这个最差情形算,不能按 LED.bg 算(那样会虚高一倍)。
    // 现值:text 11.5:1 / dim 7.4:1 / faint 4.7:1,小字(8~10pt)全部过 WCAG AA 的 4.5:1。
    // 旧值 dim 0.64 / faint 0.42 在面板上只有 4.6:1 / 2.2:1,faint 那档实测读不出来。
    static let text   = Color.white
    static let dim    = Color(white: 0.82)
    static let faint  = Color(white: 0.66)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// 标题/胶囊用的圆体(iOS 味)
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// DIN —— 工业仪表/交通标识的经典字体,macOS 自带。
    /// 用在数码管旁的单位符号(¥ % 万)和小标注上:SF Mono 的字形是给代码设计的,
    /// 摆在七段数码管边上一眼就出戏;DIN 本来就是仪表盘上的字。
    /// 万一系统缺字体,fallback 回等宽,不至于整块读数塌掉。
    static func din(_ size: CGFloat, condensed: Bool = true) -> Font {
        let name = condensed ? "DINCondensed-Bold" : "DINAlternate-Bold"
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: .bold, design: .monospaced)
    }
    /// 负载/占用语义色:绿→琥珀→红
    static func level(_ ratio: Double, warn: Double = 0.6, bad: Double = 0.85) -> Color {
        ratio >= bad ? red : (ratio >= warn ? amber : green)
    }
}

// MARK: - LED 点阵纹理(未点亮像素的残影,面板质感的关键)

struct LEDDotMatrix: View {
    var tint: Color
    var pitch: CGFloat = 5
    var alpha: Double = 0.13

    var body: some View {
        Canvas { ctx, size in
            let r: CGFloat = 1.0
            var y = pitch / 2
            while y < size.height {
                var x = pitch / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(tint.opacity(alpha)))
                    x += pitch
                }
                y += pitch
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - LED 显示面板(黑玻璃 + 中心底光 + 点阵 + 辉光;hover 微增亮)

struct LEDPanel<Content: View>: View {
    var tint: Color = LED.red
    var padding: CGFloat = 12
    var radius: CGFloat = 16
    @ViewBuilder var content: () -> Content
    /// 鼠标位置一处监听、两处用光(轮廓光 + 光斑);非 nil 即 hover 态
    @State private var mouse: CGPoint?
    private var hover: Bool { mouse != nil }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(Color.black.opacity(0.55))
                    RadialGradient(colors: [tint.opacity(hover ? 0.30 : 0.22), tint.opacity(0.05)],
                                   center: .center, startRadius: 0, endRadius: 280)
                    LEDDotMatrix(tint: tint)
                    shape.strokeBorder(tint.opacity(0.18), lineWidth: 1)
                }
                .clipShape(shape)
            }
            // 轮廓光跟着指针走(不自转):鼠标在哪一侧,哪一侧的边就亮
            .overlay {
                SweepBorder(shape: shape, color: tint, lineWidth: 1.5, drive: .follow(mouse))
            }
            .mouseSpotlight(color: tint, at: mouse, radius: 130, intensity: 0.12, clip: shape)
            .shadow(color: tint.opacity(hover ? 0.30 : 0.16), radius: hover ? 13 : 8)
            .animation(.easeOut(duration: 0.18), value: hover)
            .trackingMouse($mouse)
    }
}

// MARK: - 七段数码管(0-9、:、.、- 真七段绘制,其余字符回退等宽粗体)

struct SevenSegmentText: View {
    let text: String
    var height: CGFloat = 24
    var color: Color = LED.red
    var ghost: Double = 0.10          // 未点亮段残影(真实 LED 的关键细节)

    var body: some View {
        // 底对齐:单位符号要坐在数字基线上,居中会让 ¥ 飘在半空
        HStack(alignment: .bottom, spacing: height * 0.13) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                charView(ch)
            }
        }
        .shadow(color: color.opacity(0.9), radius: height * 0.10)
        .shadow(color: color.opacity(0.35), radius: height * 0.32)
    }

    @ViewBuilder
    private func charView(_ ch: Character) -> some View {
        if let segs = SegmentDigit.map[ch] {
            SegmentDigit(lit: segs, color: color, ghost: ghost)
                .frame(width: height * 0.52, height: height)
        } else if ch == ":" {
            VStack(spacing: height * 0.28) {
                Circle().fill(color).frame(width: height * 0.12, height: height * 0.12)
                Circle().fill(color).frame(width: height * 0.12, height: height * 0.12)
            }
            .frame(width: height * 0.14, height: height)
        } else if ch == "." {
            Circle().fill(color).frame(width: height * 0.12, height: height * 0.12)
                .frame(width: height * 0.14, height: height, alignment: .bottom)
        } else if ch == " " {
            Color.clear.frame(width: height * 0.24, height: height)
        } else {
            // ¥ $ % 万 亿 M K:这些是**单位**,不是读数的一部分。真实仪表上单位是旁边的小标注,
            // 不会做成和数字一样大的字。所以压到 46% 高、DIN 字形、稍暗——退回它该在的层级。
            Text(String(ch))
                .font(unitFont(for: ch))
                .foregroundStyle(color.opacity(0.72))
                .padding(.bottom, height * 0.06)
        }
    }

    /// 拉丁符号用 DIN(仪表字);中文单位「万/亿」DIN 没有字形,回退系统字
    private func unitFont(for ch: Character) -> Font {
        ch.isASCII ? LED.din(height * 0.52) : .system(size: height * 0.40, weight: .bold)
    }
}

/// 单个七段数码管字符。段序:0=顶 1=右上 2=右下 3=底 4=左下 5=左上 6=中
struct SegmentDigit: View {
    let lit: Set<Int>
    let color: Color
    var ghost: Double = 0.10

    var body: some View {
        Canvas { ctx, size in
            let t = size.height * 0.15
            for i in 0..<7 {
                ctx.fill(Self.segment(i, size: size, t: t),
                         with: .color(color.opacity(lit.contains(i) ? 1 : ghost)))
            }
        }
    }

    static let map: [Character: Set<Int>] = [
        "0": [0, 1, 2, 3, 4, 5], "1": [1, 2], "2": [0, 1, 6, 4, 3], "3": [0, 1, 6, 2, 3],
        "4": [5, 6, 1, 2], "5": [0, 5, 6, 2, 3], "6": [0, 5, 6, 4, 2, 3], "7": [0, 1, 2],
        "8": [0, 1, 2, 3, 4, 5, 6], "9": [0, 1, 2, 3, 5, 6], "-": [6]
    ]

    private static func segment(_ i: Int, size: CGSize, t: CGFloat) -> Path {
        let w = size.width, h = size.height
        let g = t * 0.18                      // 段间隙
        switch i {
        case 0: return hSeg(y: t / 2, x0: t / 2 + g, x1: w - t / 2 - g, t: t)
        case 6: return hSeg(y: h / 2, x0: t / 2 + g, x1: w - t / 2 - g, t: t)
        case 3: return hSeg(y: h - t / 2, x0: t / 2 + g, x1: w - t / 2 - g, t: t)
        case 5: return vSeg(x: t / 2, y0: t / 2 + g, y1: h / 2 - g, t: t)
        case 1: return vSeg(x: w - t / 2, y0: t / 2 + g, y1: h / 2 - g, t: t)
        case 4: return vSeg(x: t / 2, y0: h / 2 + g, y1: h - t / 2 - g, t: t)
        case 2: return vSeg(x: w - t / 2, y0: h / 2 + g, y1: h - t / 2 - g, t: t)
        default: return Path()
        }
    }

    /// 六边形横段
    private static func hSeg(y: CGFloat, x0: CGFloat, x1: CGFloat, t: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y))
        p.addLine(to: CGPoint(x: x0 + t / 2, y: y - t / 2))
        p.addLine(to: CGPoint(x: x1 - t / 2, y: y - t / 2))
        p.addLine(to: CGPoint(x: x1, y: y))
        p.addLine(to: CGPoint(x: x1 - t / 2, y: y + t / 2))
        p.addLine(to: CGPoint(x: x0 + t / 2, y: y + t / 2))
        p.closeSubpath()
        return p
    }

    /// 六边形竖段
    private static func vSeg(x: CGFloat, y0: CGFloat, y1: CGFloat, t: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y0))
        p.addLine(to: CGPoint(x: x + t / 2, y: y0 + t / 2))
        p.addLine(to: CGPoint(x: x + t / 2, y: y1 - t / 2))
        p.addLine(to: CGPoint(x: x, y: y1))
        p.addLine(to: CGPoint(x: x - t / 2, y: y1 - t / 2))
        p.addLine(to: CGPoint(x: x - t / 2, y: y0 + t / 2))
        p.closeSubpath()
        return p
    }
}

// MARK: - LED 圆点电平条(健身器材的灯珠条;首次出现从 0 充能)

struct LEDGauge: View {
    var ratio: Double                 // 0~1
    var color: Color
    var height: CGFloat = 8
    /// 灯珠颗数。nil = 按实际宽度算,保证任何宽度下密度一致。
    /// 固定颗数会被拉伸:30 颗摊到 640pt 宽就成了一条虚线,读不出是电平条。
    var count: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var powered = false

    var body: some View {
        GeometryReader { geo in
            let n = count ?? Self.autoCount(width: geo.size.width, dot: height)
            let lit = litCount(of: n)
            HStack(spacing: max(1.5, height * 0.34)) {
                ForEach(0..<n, id: \.self) { i in
                    Circle()
                        .fill(i < lit ? color : color.opacity(0.16))
                        .frame(width: height, height: height)
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: height, alignment: .leading)
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: lit)
        }
        .frame(height: height)
        .shadow(color: color.opacity(ratio > 0.01 ? 0.5 : 0), radius: 3)
        .onAppear {
            if reduceMotion { powered = true }
            else { withAnimation(.spring(response: 0.7, dampingFraction: 0.88).delay(0.06)) { powered = true } }
        }
    }

    /// 恒定密度:一颗灯珠 + 一条缝 ≈ 1.34 倍直径
    static func autoCount(width: CGFloat, dot: CGFloat) -> Int {
        let pitch = dot + max(1.5, dot * 0.34)
        return max(1, Int((width + max(1.5, dot * 0.34)) / pitch))
    }

    private func litCount(of n: Int) -> Int {
        let r = powered ? max(0, min(1, ratio)) : 0
        if r <= 0 { return 0 }
        return max(1, Int((r * Double(n)).rounded()))
    }
}

// MARK: - LED 灯格罩(把图表柱子切成一格格灯珠)

/// 罩在图表上的横向暗条纹:柱子被切成一段段,就成了"由灯格堆起来的柱"——
/// 真实 LED 仪表的柱状图就是这么显示的,而不是一根实心色块。
/// 底色本来就近黑,所以条纹只在柱子上看得见,不会弄脏背景。
struct LEDCellMask: View {
    var cell: CGFloat = 7          // 一格灯珠的高
    var gap: CGFloat = 2.5         // 格与格之间的暗缝

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: gap)),
                             with: .color(LED.bg))
                    y += cell + gap
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 小标注(HOURS / ACTIVE CALORIES 那种等宽大写宽字距)

struct LEDCaption: View {
    let text: String
    var tint: Color = LED.amber
    var size: CGFloat = 9

    var body: some View {
        // DIN 拉高一档字号:它是窄体,同号数视觉上比等宽小一圈
        Text(text)
            .font(LED.din(size * 1.25))
            .kerning(size * 0.26)
            .foregroundStyle(tint)
            .shadow(color: tint.opacity(0.6), radius: 3)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - 箭头列车 ‹‹‹‹ ››››(SLIDE TO ADJUST 两侧那种)

struct LEDChevrons: View {
    var pointingRight = true
    var count = 4
    var tint: Color = LED.red
    var size: CGFloat = 7

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                Image(systemName: pointingRight ? "chevron.right" : "chevron.left")
                    .font(.system(size: size, weight: .heavy))
                    .foregroundStyle(tint.opacity(opacity(at: i)))
            }
        }
        .shadow(color: tint.opacity(0.6), radius: 2)
    }

    /// 朝向一侧渐亮(视觉上的"流动感")
    private func opacity(at i: Int) -> Double {
        let f = Double(i) / Double(max(count - 1, 1))
        return pointingRight ? 0.3 + 0.7 * f : 1.0 - 0.7 * f
    }
}

// MARK: - 胶囊按钮(iOS 味:灰胶囊 / 实色选中 / 黄色 CTA;hover 增亮 + 按压缩放)

// MARK: - 幽灵按钮(全部**操作类**控件的统一语言)

/// 透明底 + 亮描边 + 细点阵 + 琥珀字。
///
/// **为什么操作按钮一律琥珀,不跟着所在面板的语义色走**:
/// 面板的颜色是在讲数据(CPU 烧红了、额度还剩绿),按钮讲的是"你能按这儿"。
/// 两件事混一个色系,红色面板里的红按钮就会读成"警告"而不是"控件"。
/// 所以:**读数用语义色,控件统一琥珀**。
///
/// **和 LEDPanel 必须一眼分得开**——它俩都是"暗底 + 点阵 + 描边",不刻意拉开就糊成一片:
/// | 维度 | 面板(屏) | 幽灵按钮(屏上的物理键) |
/// |---|---|---|
/// | 形状 | 圆角矩形 16 | 胶囊 |
/// | 描边 | tint 0.18(几乎看不见) | tint 0.5~0.95(**亮 3~5 倍,最强的区分**) |
/// | 点阵 | pitch 5(发光屏的像素) | pitch 3(更细密 = 蚀刻金属面) |
/// | 字 | 读数=语义色 / 正文=白 | 一律琥珀 |
/// | 反馈 | 不动 | hover 通电、按下回弹 |
struct LEDGhostButtonStyle: ButtonStyle {
    var tint: Color = LED.amber
    var size: CGFloat = 10
    /// 主 CTA(打开监控台 / 清理选中):边更粗、常驻底光更足——不靠实色填充也压得住场
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, tint: tint, size: size, prominent: prominent)
    }

    private struct Chrome: View {
        let configuration: Configuration
        let tint: Color
        let size: CGFloat
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            let lit = hover || pressed          // "通电"态:hover 和按下共用,省一套状态
            configuration.label
                .font(LED.display(size, .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, prominent ? 16 : 11)
                .padding(.vertical, prominent ? 7 : 4.5)
                .background {
                    ZStack {
                        // 底几乎是空的(所以叫"幽灵"),只有通电时透出一点琥珀
                        Capsule().fill(tint.opacity(lit ? 0.16 : 0.06))
                        // 顶沿一道极淡高光:光打在实体键上的样子,质感全靠这层
                        Capsule().fill(LinearGradient(colors: [.white.opacity(0.07), .clear],
                                                      startPoint: .top, endPoint: .center))
                        LEDDotMatrix(tint: tint, pitch: 3, alpha: lit ? 0.22 : 0.14)
                        Capsule().strokeBorder(tint.opacity(lit ? 0.95 : (prominent ? 0.7 : 0.5)),
                                               lineWidth: prominent ? 1.5 : 1)
                    }
                    .clipShape(Capsule())
                }
                .shadow(color: tint.opacity(lit ? 0.5 : (prominent ? 0.25 : 0.10)), radius: lit ? 9 : 5)
                .opacity(isEnabled ? 1 : 0.3)
                .scaleEffect(pressed && !reduceMotion ? 0.95 : 1)
                .animation(.easeOut(duration: 0.12), value: lit)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
                .onHover { hover = isEnabled && $0 }
        }
    }
}

// MARK: - 实色胶囊按钮(仅**选中态**用:页签、筛选器那种"当前是哪个"的指示)
// 操作类按钮别用这个,用 LEDGhostButtonStyle。

struct LEDPillButtonStyle: ButtonStyle {
    var fill: Color = LED.chrome
    var foreground: Color = .white
    var size: CGFloat = 11
    var glow: Bool = false            // 实色胶囊(选中态/CTA)带辉光

    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, fill: fill, foreground: foreground, size: size, glow: glow)
    }

    private struct Chrome: View {
        let configuration: Configuration
        let fill: Color
        let foreground: Color
        let size: CGFloat
        let glow: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(LED.display(size, .bold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(fill).brightness(hover ? 0.08 : 0))
                .shadow(color: glow ? fill.opacity(hover ? 0.55 : 0.35) : .clear, radius: hover ? 10 : 6)
                .opacity((pressed ? 0.75 : 1) * (isEnabled ? 1 : 0.35))
                .scaleEffect(pressed && !reduceMotion ? 0.95 : 1)
                .animation(.easeOut(duration: 0.12), value: hover)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
                .onHover { hover = isEnabled && $0 }
        }
    }
}

// MARK: - LED 输入框(自绘占位符)

/// 输入框:chrome 胶囊底 + 白色输入文字 + 自绘占位符。
///
/// 为什么不用 TextField 自带的占位符:它的颜色写死在系统 placeholderTextColor 上,
/// `.foregroundStyle` 只作用于**已输入的文字**,管不到占位符(实测取色:输入文字 #fff,
/// 占位符 #999 = white 0.60)。0.60 灰配 chrome 胶囊只有 6:1,10pt 中文笔画细,实际读不出来。
/// 所以传空 prompt、自己叠一层 Text,颜色用 LED.dim(10.6:1)——
/// 输入文字仍是纯白,两者亮度差得开,占位符不会被误读成已输入内容。
struct LEDTextField: View {
    let placeholder: String
    @Binding var text: String
    var size: CGFloat = 10

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(LED.mono(size))
            .foregroundStyle(LED.text)
            .overlay(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(LED.mono(size))
                        .foregroundStyle(LED.dim)
                        .lineLimit(1)
                        .allowsHitTesting(false)   // 别挡住点击聚焦
                }
            }
    }
}

// MARK: - 列表行悬停(LED 版:琥珀指示线)

private struct LEDHoverHighlight: ViewModifier {
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .background(hover ? Color.white.opacity(0.05) : .clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(alignment: .leading) {
                if hover {
                    Capsule().fill(LED.amber.opacity(0.9)).frame(width: 2)
                        .shadow(color: LED.amber.opacity(0.7), radius: 2)
                }
            }
            .padding(.horizontal, -4)
            .animation(.easeOut(duration: 0.12), value: hover)
            .onHover { hover = $0 }
    }
}

extension View {
    /// LED 列表行:悬停打亮 + 左缘琥珀指示线
    func ledRowHover() -> some View { modifier(LEDHoverHighlight()) }
}
