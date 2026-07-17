import SwiftUI

// MARK: - 卡片容器(主题感知):
// 经典 = 玻璃卡(material 底 + 圆角 + 镜面光边 + 阴影 + hover 抬升)
// HUD  = 暗面板 + 发丝线 + 四角括号,hover 时括号提亮微抬
// LED  = 近黑圆角卡 + 极淡点阵 + 琥珀细描边,hover 时底光微亮 + 抬升 + 琥珀外发光

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content
    @ObservedObject private var settings = DisplaySettings.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 鼠标位置一处监听、两处用光(轮廓光 + 光斑);非 nil 即 hover 态。
    /// 经典主题没有光效,只取 hover 抬升,位置本身用不上。
    @State private var mouse: CGPoint?
    private var hover: Bool { mouse != nil }

    var body: some View {
        if settings.isLED { ledBody }
        else if settings.isHUD { hudBody }
        else { classicBody }
    }

    private var inner: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// LED 卡不用 LEDPanel:面板容器没有 hover 抬升,而卡片列表需要和经典/HUD 一致的抬升反馈。
    private var ledBody: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return inner
            .background {
                ZStack {
                    shape.fill(LED.bg)
                    // 中心向外的底光,hover 时增亮(仪表"通电"感)
                    RadialGradient(colors: [LED.amber.opacity(hover ? 0.11 : 0.05), LED.amber.opacity(0.01)],
                                   center: .center, startRadius: 0, endRadius: 300)
                    LEDDotMatrix(tint: LED.amber, pitch: 6, alpha: 0.05)
                    shape.strokeBorder(LED.amber.opacity(hover ? 0.34 : 0.16), lineWidth: 1)
                }
                .clipShape(shape)
            }
            .overlay {
                SweepBorder(shape: shape, color: LED.amber, lineWidth: 1.5, drive: .follow(mouse))
            }
            .mouseSpotlight(color: LED.amber, at: mouse, radius: 160, intensity: 0.10, clip: shape)
            .shadow(color: LED.amber.opacity(hover ? 0.22 : 0.05), radius: hover ? 14 : 8)
            .offset(y: hover && !reduceMotion ? -2 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: hover)
            .trackingMouse($mouse)
    }

    private var hudBody: some View {
        inner
            .background {
                ZStack {
                    Rectangle().fill(HUD.panel.opacity(hover ? 0.92 : 0.78))
                    Rectangle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                    CornerBrackets(length: 8)
                        .stroke(HUD.cyan.opacity(hover ? 0.9 : 0.5), lineWidth: 1)
                }
            }
            .overlay {
                SweepBorder(shape: Rectangle(), color: HUD.cyan, lineWidth: 1, drive: .follow(mouse))
            }
            .mouseSpotlight(color: HUD.cyan, at: mouse, radius: 150, intensity: 0.09, clip: Rectangle())
            .shadow(color: HUD.cyan.opacity(hover ? 0.10 : 0), radius: 14)
            .offset(y: hover && !reduceMotion ? -2 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: hover)
            .trackingMouse($mouse)
    }

    private var classicBody: some View {
        inner
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(reduceTransparency
                          ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                          : AnyShapeStyle(.regularMaterial))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            }
            .shadow(color: .black.opacity(hover ? 0.14 : 0.08), radius: hover ? 16 : 10, y: hover ? 7 : 4)
            .offset(y: hover && !reduceMotion ? -2 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
            .trackingMouse($mouse)
    }
}

// MARK: - 指标磁贴(大数值 + 环比 chip,数值走弹簧滚动)
// LED 下大数值走七段数码管,accent 决定读数颜色(默认琥珀=金钱/用量)。

struct MetricTile: View {
    let title: String
    let value: String
    var delta: Double? = nil
    var deltaAbsolute: String? = nil
    var deltaContext: String? = nil
    var subtitle: String? = nil
    var accent: Color? = nil
    /// LED 专用的英文代号小标注(经典/HUD 忽略),如 "TOTAL COST"
    var code: String? = nil
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        Group {
            if settings.isLED { ledBody } else { plainBody }
        }
        // LED 数字由 Canvas 绘制，VoiceOver 无法自行读取；整块磁贴统一提供语义值。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts = [value]
        if let delta {
            parts.append(delta >= 0
                         ? "增加 \(String(format: "%.0f", abs(delta) * 100))%"
                         : "减少 \(String(format: "%.0f", abs(delta) * 100))%")
        }
        if let deltaAbsolute { parts.append(deltaAbsolute) }
        if let deltaContext { parts.append(deltaContext) }
        if let subtitle { parts.append(subtitle) }
        return parts.joined(separator: "，")
    }

    private var ledBody: some View {
        let tint = accent ?? LED.amber
        return VStack(alignment: .leading, spacing: 6) {
            if let code { LEDCaption(text: code, tint: tint, size: 9) }
            Text(title).font(LED.display(10, .medium)).foregroundStyle(LED.dim).lineLimit(1)
            // 七段字符是固定宽度画的,长读数(如 ¥12,345.67)得整体降档才不撑破磁贴
            ViewThatFits(in: .horizontal) {
                SevenSegmentText(text: value, height: 24, color: tint)
                SevenSegmentText(text: value, height: 19, color: tint)
                SevenSegmentText(text: value, height: 15, color: tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            details(font: LED.mono(8), color: LED.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var plainBody: some View {
        VStack(alignment: .leading, spacing: settings.isHUD ? 6 : 5) {
            if settings.isHUD {
                HStack(spacing: 5) {
                    Rectangle().fill(accent ?? HUD.cyan).frame(width: 2, height: 8)
                    Text(title).font(.system(size: 10)).foregroundStyle(HUD.dim)
                }
            } else {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value)
                .font(settings.isHUD ? HUD.mono(23, .bold)
                                     : .system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(settings.isHUD ? HUD.text : Color.primary)
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            details(font: settings.isHUD ? HUD.mono(8) : .caption2,
                    color: settings.isHUD ? HUD.faint : Color.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func details(font: Font, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if delta != nil || deltaContext != nil || deltaAbsolute != nil {
                HStack(spacing: 5) {
                    if let delta { DeltaChip(delta: delta) }
                    if let deltaAbsolute {
                        Text(deltaAbsolute).foregroundStyle(color)
                    }
                    if let deltaContext {
                        Text(deltaContext).foregroundStyle(color)
                    }
                }
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            if let subtitle {
                Text(subtitle)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }
}

/// 环比 chip:↑ 红 / ↓ 绿(花费下降是好事)
struct DeltaChip: View {
    let delta: Double
    @ObservedObject private var settings = DisplaySettings.shared
    var body: some View {
        let up = delta >= 0
        let color: Color = settings.isLED ? (up ? LED.red : LED.green)
                         : settings.isHUD ? (up ? HUD.red : HUD.green)
                                          : (up ? Color.red : Color.green)
        return HStack(spacing: 2) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
            Text(String(format: "%.0f%%", abs(delta) * 100))
        }
        .font(settings.isLED ? LED.mono(9, .bold)
              : settings.isHUD ? HUD.mono(9, .semibold) : .system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, settings.isHUD ? 5 : 6).padding(.vertical, 2)
        .background {
            if settings.isLED {
                // LED 是 iOS 味圆角:胶囊 + 描边 + 辉光,不用切角
                ZStack {
                    Capsule().fill(color.opacity(0.14))
                    Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1)
                }
            } else if settings.isHUD {
                ZStack {
                    CutCorner(cut: 3).fill(color.opacity(0.12))
                    CutCorner(cut: 3).stroke(color.opacity(0.4), lineWidth: 1)
                }
            } else {
                Capsule().fill(color.opacity(0.12))
            }
        }
        .shadow(color: settings.isLED ? color.opacity(0.4) : .clear, radius: 4)
    }
}

// MARK: - 分区标题(经典:图标+headline;HUD:▎标题 ────;LED:CODE + 中文 + 淡线)

struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var trailing: AnyView? = nil
    @ObservedObject private var settings = DisplaySettings.shared

    /// LED 小标注只认已知分区;映射不到就只显示中文标题(不硬造英文)
    private static let ledCodes: [String: String] = [
        "等价成本趋势": "EST. COST TREND",
        "使用洞察": "INSIGHTS",
        "Token 构成": "TOKEN MIX",
        "按模型": "BY MODEL",
        "按项目": "BY PROJECT"
    ]

    var body: some View {
        if settings.isLED {
            HStack(spacing: 8) {
                if let code = Self.ledCodes[title] { LEDCaption(text: code, tint: LED.amber, size: 9) }
                Text(title).font(LED.display(12, .semibold)).foregroundStyle(LED.text)
                    .fixedSize()
                Rectangle().fill(LED.amber.opacity(0.14)).frame(height: 1)
                if let trailing { trailing }
            }
        } else if settings.isHUD {
            HStack(spacing: 7) {
                Rectangle().fill(HUD.cyan).frame(width: 2, height: 10)
                if let icon {
                    Image(systemName: icon).font(.system(size: 10)).foregroundStyle(HUD.dim)
                }
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(HUD.text)
                    .fixedSize()
                Rectangle().fill(HUD.gridline).frame(height: 1)
                if let trailing { trailing }
            }
        } else {
            HStack {
                if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
                Text(title).font(.headline)
                Spacer()
                if let trailing { trailing }
            }
        }
    }
}

// MARK: - 模型/项目稳定配色(按 key 哈希取色板,色板跟随主题)

enum SeriesColor {
    static let classicPalette: [Color] = [
        .blue, .purple, .teal, .orange, .pink, .green, .indigo, .cyan, .mint, .red
    ]
    static let hudPalette: [Color] = [
        HUD.cyan, HUD.violet, HUD.mint, HUD.amber, HUD.pink,
        HUD.green, HUD.ice, Color(red: 1.0, green: 0.55, blue: 0.30),
        Color(red: 0.45, green: 0.62, blue: 1.0), HUD.red
    ]
    /// LED 单色亮度阶梯(琥珀系)。
    /// **真实的 LED 仪表盘是单色的**——参考图里时间是纯红屏、卡路里是纯琥珀屏,
    /// 多个系列在真机上靠亮度区分,不靠色相。之前用 10 个全饱和高亮色(红/绿/玫红/薄荷…)
    /// 糊在近黑底上,又刺眼又不像仪表。这里收成一条从亮金到暗铜的暖色阶梯:
    /// 眼睛舒服,而且整块屏读起来仍是"一块 LED 屏"。
    static let ledPalette: [Color] = [
        Color(red: 1.00, green: 0.84, blue: 0.32),   // 亮金
        Color(red: 1.00, green: 0.62, blue: 0.04),   // 琥珀(主色)
        Color(red: 0.94, green: 0.72, blue: 0.44),   // 沙
        Color(red: 0.96, green: 0.44, blue: 0.10),   // 橙
        Color(red: 0.78, green: 0.58, blue: 0.30),   // 麦
        Color(red: 0.80, green: 0.32, blue: 0.08),   // 深橙
        Color(red: 0.62, green: 0.46, blue: 0.24),   // 暗麦
        Color(red: 0.58, green: 0.26, blue: 0.08)    // 暗铜
    ]
    @MainActor
    static var palette: [Color] {
        switch DisplaySettings.shared.theme {
        case .led: return ledPalette
        case .hud: return hudPalette
        case .classic: return classicPalette
        }
    }
    @MainActor
    static func color(for key: String) -> Color {
        var h = 5381
        for b in key.utf8 { h = ((h << 5) &+ h) &+ Int(b) }
        return palette[Int(h.magnitude % UInt(palette.count))]
    }
}

// MARK: - 按压缩放按钮风格

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}
