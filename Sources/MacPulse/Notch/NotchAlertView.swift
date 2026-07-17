import SwiftUI

/// 刘海强提醒内容:一个从刘海下方滑出的深色胶囊(仿灵动岛),含图标/进度环 + 标题副标题。
/// 自带进场(弹簧下滑)+ duration 后退场动画,退场结束回调 onFinished 关闭浮层。
/// 皮肤跟随全局主题:经典 = 圆角胶囊;HUD = 切角面板 + 四角括号;LED = 圆角 LED 屏 + 分段灯环。
struct NotchAlertView: View {
    let alert: NotchAlert
    let duration: TimeInterval
    let topInset: CGFloat          // 刘海高度,胶囊从这条线之下滑出
    let notchWidth: CGFloat?
    let onFinished: () -> Void

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = DisplaySettings.shared

    private var hud: Bool { settings.isHUD }
    private var led: Bool { settings.isLED }

    var body: some View {
        VStack {
            pill
                .offset(y: shown ? 0 : -80)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.9, anchor: .top)
            Spacer(minLength: 0)
        }
        .padding(.top, max(topInset - 2, 4))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .onAppear(perform: run)
    }

    private var pill: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(alert.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 320)
        .background {
            if led { ledShell } else if hud { hudShell } else { classicShell }
        }
        // 轮廓扫光:和弹窗/监控台/刘海面板同一套语言。
        // 这里是**全app唯一**还自转的光:提醒浮层 ignoresMouseEvents(只展示不挡点击),
        // 鼠标根本够不着,跟随光在这儿无从谈起;而且它只闪几秒就消失,自转正好用来引一下注意力。
        // 经典主题不参与,保持原生质感。
        .overlay {
            if led {
                SweepBorder(shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                            color: alert.tint, lineWidth: 1.5, drive: .auto(period: 3.4))
            } else if hud {
                SweepBorder(shape: CutCorner(cut: 10, corners: .diagonal),
                            color: alert.tint, lineWidth: 1, drive: .auto(period: 2.6))
            }
        }
        .shadow(color: hud || led ? alert.tint.opacity(led ? 0.3 : 0.25) : .black.opacity(0.4),
                radius: 16, y: 8)
    }

    /// LED 外壳:毛玻璃垫底 + iOS 味圆角 LED 屏(近黑罩 + 中心底光 + 点阵 + tint 描边)
    private var ledShell: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return ZStack {
            HUDBlurView(material: .hudWindow)
            Color.black.opacity(0.72)
            RadialGradient(colors: [alert.tint.opacity(0.24), alert.tint.opacity(0.04), .clear],
                           center: .center, startRadius: 0, endRadius: 190)
            LEDDotMatrix(tint: alert.tint)
            shape.strokeBorder(alert.tint.opacity(0.5), lineWidth: 1)
        }
        .clipShape(shape)
    }

    /// HUD 外壳:毛玻璃垫底 + 切角深空面板 + 色调发丝线 + 四角括号
    private var hudShell: some View {
        ZStack {
            HUDBlurView(material: .hudWindow)
                .clipShape(CutCorner(cut: 10, corners: .diagonal))
            CutCorner(cut: 10, corners: .diagonal)
                .fill(LinearGradient(colors: [Color.black.opacity(0.85), HUD.panel.opacity(0.55)],
                                     startPoint: .top, endPoint: .bottom))
            CutCorner(cut: 10, corners: .diagonal)
                .stroke(alert.tint.opacity(0.55), lineWidth: 1)
            CornerBrackets(length: 8)
                .stroke(alert.tint.opacity(0.9), lineWidth: 1.5)
                .padding(3)
        }
    }

    /// 经典外壳:毛玻璃垫底 + 圆角深色胶囊 + 色调描边
    private var classicShell: some View {
        ZStack {
            HUDBlurView(material: .hudWindow)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.06).opacity(0.8))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(alert.tint.opacity(0.5), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var leading: some View {
        if let p = alert.progress, led {
            // LED 主题用分段灯珠环(描边圆环是经典/HUD 的语言)
            ZStack {
                LEDRing(progress: p, color: alert.tint)
                Image(systemName: alert.icon).font(.system(size: 12, weight: .bold))
                    .foregroundStyle(alert.tint)
                    .shadow(color: alert.tint.opacity(0.8), radius: 3)
            }
            .frame(width: 34, height: 34)
        } else if led {
            ZStack {
                Circle().fill(alert.tint.opacity(0.18)).frame(width: 34, height: 34)
                Circle().strokeBorder(alert.tint.opacity(0.5), lineWidth: 1).frame(width: 34, height: 34)
                Image(systemName: alert.icon).font(.system(size: 15, weight: .bold))
                    .foregroundStyle(alert.tint)
                    .shadow(color: alert.tint.opacity(0.85), radius: 4)
            }
        } else if let p = alert.progress {
            ZStack {
                if hud {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
                    Circle().trim(from: 0, to: max(0.02, min(1, p)))
                        .stroke(alert.tint, style: StrokeStyle(lineWidth: 3, lineCap: .butt, dash: [3, 1.6]))
                        .rotationEffect(.degrees(-90))
                } else {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 4)
                    Circle().trim(from: 0, to: max(0.02, min(1, p)))
                        .stroke(alert.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: alert.icon).font(.system(size: 12, weight: .bold))
                    .foregroundStyle(alert.tint)
            }
            .frame(width: 34, height: 34)
        } else if hud {
            ZStack {
                Rectangle().fill(alert.tint.opacity(0.14)).frame(width: 34, height: 34)
                CornerBrackets(length: 5).stroke(alert.tint.opacity(0.8), lineWidth: 1)
                    .frame(width: 34, height: 34)
                Image(systemName: alert.icon).font(.system(size: 15, weight: .bold))
                    .foregroundStyle(alert.tint)
                    .shadow(color: alert.tint.opacity(0.7), radius: 4)
            }
        } else {
            ZStack {
                Circle().fill(alert.tint.opacity(0.2)).frame(width: 34, height: 34)
                Image(systemName: alert.icon).font(.system(size: 16, weight: .bold))
                    .foregroundStyle(alert.tint)
            }
        }
    }

    private func run() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.72)) {
            shown = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeIn(duration: 0.35)) { shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onFinished() }
        }
    }
}

/// 分段 LED 灯珠环:一圈灯珠按 progress 比例点亮(12 点方向起,顺时针)
private struct LEDRing: View {
    let progress: Double
    let color: Color
    var count: Int = 20
    var dot: CGFloat = 2.6
    var radius: CGFloat = 15

    var body: some View {
        let lit = max(1, Int((max(0, min(1, progress)) * Double(count)).rounded()))
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i < lit ? color : color.opacity(0.16))
                    .frame(width: dot, height: dot)
                    .shadow(color: i < lit ? color.opacity(0.8) : .clear, radius: 2)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(i) / Double(count) * 360))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: lit)
    }
}
