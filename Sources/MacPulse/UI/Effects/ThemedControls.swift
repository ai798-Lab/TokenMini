import SwiftUI

// MARK: - 主题化通用控件
// 系统原生的 .pickerStyle(.segmented) / .buttonStyle(.bordered) 在 HUD/LED 下是纯粹的异物
// (一块系统蓝的圆角控件),这里按三主题各画一套。经典主题仍走系统原生——那正是它的本色。

/// 当前主题的强调色(HUD 青 / LED 琥珀 / 经典 accentColor)
@MainActor
func themeAccent() -> Color {
    let s = DisplaySettings.shared
    if s.isLED { return LED.amber }
    if s.isHUD { return HUD.cyan }
    return .accentColor
}

// MARK: 分段选择器

/// 主题化分段控件:替代 .pickerStyle(.segmented)。
/// HUD = 切角 + 代号感;LED = 圆角胶囊 + 辉光;经典 = 系统原生 Picker。
struct ThemedSegmented<T: Hashable>: View {
    let items: [(value: T, label: String)]
    @Binding var selection: T
    /// 选中态颜色,nil = 跟随主题强调色
    var accent: Color? = nil
    var size: CGFloat = 10

    @ObservedObject private var settings = DisplaySettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns

    private var tint: Color { accent ?? themeAccent() }

    var body: some View {
        if settings.isDarkSkin { skinned } else { native }
    }

    private var native: some View {
        Picker("", selection: $selection) {
            ForEach(items, id: \.value) { Text($0.label).tag($0.value) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// 只有选中态画 chrome,未选中裸在背景上(和弹窗页签同一套语言);
    /// 也不加容器底槽——底槽会把这组控件压成一块沉甸甸的"系统分段控件"。
    /// 未选中**照样是亮字**:"没有 chrome" 不等于 "变暗",灰字会读成禁用态。
    private var skinned: some View {
        HStack(spacing: settings.isLED ? 8 : 3) {
            ForEach(items, id: \.value) { item in
                let on = selection == item.value
                Button {
                    if reduceMotion { selection = item.value }
                    else { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = item.value } }
                } label: {
                    Text(item.label)
                        .font(settings.isLED ? LED.display(size, on ? .bold : .medium)
                                             : HUD.mono(size, on ? .bold : .medium))
                        .foregroundStyle(labelColor(on))
                        .padding(.horizontal, settings.isLED ? (on ? 11 : 2) : 9)
                        .padding(.vertical, 4)
                        .background { chrome(on) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize()
    }

    private func labelColor(_ on: Bool) -> Color {
        if !on { return settings.isLED ? LED.text : HUD.dim }
        // LED 选中是实色灯面,字要压深色才看得清;HUD 选中是半透明填充,字用亮色
        return settings.isLED ? LED.bg : HUD.text
    }

    @ViewBuilder
    private func chrome(_ on: Bool) -> some View {
        if on {
            if settings.isLED {
                Capsule().fill(tint)
                    .shadow(color: tint.opacity(0.5), radius: 5)
                    .matchedGeometryEffect(id: "seg.chrome", in: ns)
            } else {
                ZStack(alignment: .bottom) {
                    CutCorner(cut: 4).fill(tint.opacity(0.14))
                    CutCorner(cut: 4).stroke(tint.opacity(0.55), lineWidth: 1)
                    Rectangle().fill(tint).frame(height: 1.5)
                        .padding(.horizontal, 4)
                        .shadow(color: tint.opacity(0.8), radius: 2)
                }
                .matchedGeometryEffect(id: "seg.chrome", in: ns)
            }
        }
    }
}

// MARK: 菜单按钮外壳

/// 主题化菜单标签:替代 .buttonStyle(.bordered) 的 Menu label。
/// n > 0 时点亮(表示该维度有筛选)。
struct ThemedMenuLabel: View {
    let title: String
    var count: Int = 0
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        let on = count > 0
        let tint = themeAccent()
        HStack(spacing: 4) {
            Text(count == 0 ? title : "\(title) · \(count)")
                .font(settings.isLED ? LED.display(10, on ? .bold : .medium)
                      : (settings.isHUD ? HUD.mono(10, on ? .bold : .medium) : .caption))
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .opacity(0.7)
        }
        .foregroundStyle(skinnedForeground(on: on, tint: tint))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background { menuChrome(on: on, tint: tint) }
    }

    private func skinnedForeground(on: Bool, tint: Color) -> Color {
        guard settings.isDarkSkin else { return on ? tint : .primary }
        if on { return tint }
        return settings.isLED ? LED.dim : HUD.dim
    }

    @ViewBuilder
    private func menuChrome(on: Bool, tint: Color) -> some View {
        if settings.isLED {
            ZStack {
                Capsule().fill(on ? tint.opacity(0.14) : Color.white.opacity(0.06))
                if on { Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1) }
            }
        } else if settings.isHUD {
            ZStack {
                CutCorner(cut: 4).fill(on ? tint.opacity(0.12) : Color.white.opacity(0.04))
                CutCorner(cut: 4).stroke(on ? tint.opacity(0.5) : Color.white.opacity(0.10), lineWidth: 1)
            }
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .controlColor))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
        }
    }
}

// MARK: 图表图例

/// 主题化图例:替代 Charts 自带的 .chartLegend(系统字体 + 圆点,在 HUD/LED 下很出戏)。
/// 颜色必须与图表的 chartForegroundStyleScale 用同一套映射(都走 SeriesColor)。
struct ThemedChartLegend: View {
    let series: [String]
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        // 系列多时自动换行,别撑破卡片
        FlowLayout(spacing: 10, lineSpacing: 5) {
            ForEach(series, id: \.self) { s in
                HStack(spacing: 5) {
                    marker(SeriesColor.color(for: s))
                    Text(s)
                        .font(settings.isLED ? LED.din(11)
                              : (settings.isHUD ? HUD.mono(9) : .caption2))
                        .foregroundStyle(settings.isLED ? LED.dim
                                         : (settings.isHUD ? HUD.dim : Color.secondary))
                        .lineLimit(1)
                }
            }
        }
    }

    /// HUD 用方块,LED/经典用圆点(LED 的带辉光)——与各主题其它图例保持一致
    @ViewBuilder
    private func marker(_ c: Color) -> some View {
        if settings.isHUD {
            Rectangle().fill(c).frame(width: 6, height: 6)
        } else {
            Circle().fill(c).frame(width: 7, height: 7)
                .shadow(color: settings.isLED ? c.opacity(0.8) : .clear, radius: 3)
        }
    }
}

/// 简易流式布局(图例用):按行排,超宽换行
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW {
                x = 0; y += lineH + lineSpacing; lineH = 0
            }
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                x = bounds.minX; y += lineH + lineSpacing; lineH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}
