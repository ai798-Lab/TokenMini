import SwiftUI

// MARK: - 扫光效果(轮廓跟随光 + 鼠标跟随光斑)
// 原生实现,不引三方库:现成的 shimmer 库做的是骨架屏闪烁,做不到"跟随主题色 + 沿轮廓走"。
//
// 默认**跟着鼠标走,不自动播放**:光是"照明",指针在哪就照哪。自动循环的光有两个毛病——
// 一是没人看的时候还在自己转,是噪音;二是在刘海面板上会一路扫进菜单栏,和物理刘海割裂。
// 唯一的例外是刘海提醒浮层(ignoresMouseEvents,鼠标根本够不着),那儿只能 .auto。
//
// 一个容器只挂一次 `trackingMouse`,拿到的位置同时喂给轮廓光和光斑:两处光同源才不会打架。

/// 光的驱动方式
enum SweepDrive {
    /// 跟着鼠标走(视图本地坐标;nil = 指针不在视图里 → 只留底描边)
    case follow(CGPoint?)
    /// 自动循环,值为转一圈的秒数。只给鼠标够不着的浮层用。
    case auto(period: Double)
}

// MARK: 鼠标位置来源

private struct MouseTracker: ViewModifier {
    @Binding var location: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            switch phase {
            case .active(let p):
                // 跟手要跟得紧,不加动画;只有出现/消失走淡入淡出
                if location == nil, !reduceMotion {
                    withAnimation(.easeOut(duration: 0.18)) { location = p }
                } else {
                    location = p
                }
            case .ended:
                if reduceMotion { location = nil }
                else { withAnimation(.easeOut(duration: 0.25)) { location = nil } }
            }
        }
    }
}

extension View {
    /// 把视图内的鼠标位置写进 binding(离开为 nil)。
    /// 刘海面板不能用它:非激活浮层上 SwiftUI 的 hover 回调不可靠,那边由 NotchDock 的全局鼠标监听直接喂位置。
    func trackingMouse(_ location: Binding<CGPoint?>) -> some View {
        modifier(MouseTracker(location: location))
    }
}

// MARK: 轮廓光

/// 鼠标模式按实际距离照亮附近轮廓，远端描边保持原样。
/// 自动模式保留沿轮廓旋转的 AngularGradient，仅用于鼠标无法触及的提醒浮层。
struct SweepBorder<S: Shape>: View {
    var shape: S
    var color: Color = HUD.cyan
    var lineWidth: CGFloat = 1
    /// 高光弧长占整圈的比例(越小越像一道窄光)
    var arc: Double = 0.14
    /// Pointer light is local, not an angular beam projected across the whole card.
    var radius: CGFloat = 96
    /// 常驻底描边(高光之外的部分),nil = 不画
    var base: Color? = nil
    var drive: SweepDrive

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let base { shape.stroke(base, lineWidth: lineWidth) }
            switch drive {
            case .follow(let p):
                GeometryReader { geo in
                    if let p {
                        shape.stroke(color.opacity(0.95), lineWidth: lineWidth)
                            .mask {
                                RadialGradient(colors: [.white, .clear],
                                               center: UnitPoint(x: p.x / max(geo.size.width, 1),
                                                                 y: p.y / max(geo.size.height, 1)),
                                               startRadius: 0, endRadius: radius)
                            }
                            .shadow(color: color.opacity(0.5), radius: lineWidth * 2.5)
                            .transition(.opacity)
                    }
                }
            case .auto(let period):
                if reduceMotion {
                    // 减弱动态效果:不转,给一圈静态微光,保持轮廓质感
                    shape.stroke(color.opacity(0.35), lineWidth: lineWidth)
                } else {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let phase = (t.truncatingRemainder(dividingBy: period)) / period
                        lit(angle: .degrees(phase * 360))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func lit(angle: Angle) -> some View {
        shape
            .stroke(gradient(angle: angle), lineWidth: lineWidth)
            .shadow(color: color.opacity(0.5), radius: lineWidth * 2.5)
    }

    /// 把"一段亮弧"铺成角度渐变:除高光区外全透明,高光区两端淡入淡出
    private func gradient(angle: Angle) -> AngularGradient {
        let stops: [Gradient.Stop] = [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: max(0, 0.5 - arc)),
            .init(color: color.opacity(0.9), location: 0.5),
            .init(color: .clear, location: min(1, 0.5 + arc)),
            .init(color: .clear, location: 1),
        ]
        return AngularGradient(gradient: Gradient(stops: stops), center: .center, angle: angle)
    }
}

// MARK: 鼠标跟随光斑

extension View {
    /// 鼠标跟随光斑。位置由调用方喂进来(`trackingMouse` 或外部鼠标监听),
    /// 这样同一个容器里的轮廓光和光斑用的是同一个位置。
    /// clip 传容器形状,保证光不溢出圆角/切角之外。color 传 nil = 完全不生效(经典主题:没特效就是它的身份)。
    func mouseSpotlight<S: Shape>(color: Color?, at: CGPoint?, radius: CGFloat = 120,
                                  intensity: Double = 0.13, clip: S) -> some View {
        overlay {
            if let color, let at {
                GeometryReader { geo in
                    RadialGradient(colors: [color.opacity(intensity), .clear],
                                   center: UnitPoint(x: at.x / max(geo.size.width, 1),
                                                     y: at.y / max(geo.size.height, 1)),
                                   startRadius: 0, endRadius: radius)
                    .blendMode(.plusLighter)      // 叠加而非覆盖,不糊掉底下的读数
                    .transition(.opacity)
                }
                .allowsHitTesting(false)
            }
        }
        .clipShape(clip)
    }
}
