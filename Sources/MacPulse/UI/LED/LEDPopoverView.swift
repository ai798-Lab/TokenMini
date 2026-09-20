import SwiftUI
import AppKit

/// LED 主题主面板(复古健身器材仪表风):近黑底 + 圆体标头 + 胶囊页签。
/// 与 HUD/经典版功能、话术、数据源完全一致,只换视觉语言。
/// 窗体保留系统圆角(HUDWindowShaper 只对 HUD 生效)——LED 是 iOS 味,不做切角。
struct LEDPopoverView: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var usage: UsageStore
    @AppStorage("macpulse.proMode") private var proMode = false
    @State private var tab: Tab = .system
    @Namespace private var tabNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Tab: String, CaseIterable, Identifiable {
        case system = "系统"
        case ai = "AI 用量"
        case skills = "Skills"
        var id: String { rawValue }

        /// 配色规则:一类功能一种 LED 色——切页签时整块面板的色调随之改变。
        var tint: Color {
            switch self {
            case .system: return LED.red      // 系统负载
            case .ai: return LED.amber        // 金钱/用量
            case .skills: return LED.green    // 健康/成功
            }
        }

        var icon: String {
            switch self {
            case .system: return "cpu"
            case .ai: return "flame.fill"
            case .skills: return "puzzlepiece.extension.fill"
            }
        }
    }

    /// 当前主色:专业模式跟随页签,简单模式固定琥珀(首页主角是花费)。
    private var accent: Color { proMode ? tab.tint : LED.amber }

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            // 窗口尺寸定死(否则 MenuBarExtra(.window) 随内容重排,切换瞬间圆角闪失),超高内容滚动。
            HUDScrollView(accent: LED.amber) {
                Group {
                    if proMode {
                        proContent
                    } else {
                        LEDSimpleHomeView()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            hairline
            footer
        }
        .frame(width: 340, height: 560)
        .background {
            ZStack {
                LED.bg
                // 顶部一层极淡的主色环境光:切页签时整个面板"换色"的底噪,不抢面板辉光。
                RadialGradient(colors: [accent.opacity(0.07), .clear],
                               center: .top, startRadius: 0, endRadius: 300)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.3), value: accent)
        }
        .tint(LED.amber)
        .preferredColorScheme(.dark)
    }

    private var hairline: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    // MARK: 顶部标头

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark().foregroundStyle(LED.green)
            VStack(alignment: .leading, spacing: 0) {
                Text("TOKENMINI")
                    .font(LED.display(15, .bold))
                    .foregroundStyle(LED.text)
                Text(proMode ? "专业模式" : "系统监控器")
                    .font(LED.display(9.5, .medium))
                    .foregroundStyle(LED.dim)
            }
            Spacer()
            DisplaySettingsMenu()
                .foregroundStyle(LED.dim)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { proMode.toggle() }
            } label: {
                Text(proMode ? "简单" : "专业")
            }
            .buttonStyle(LEDGhostButtonStyle(size: 10))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10).padding(.bottom, 8)
    }

    private var proContent: some View {
        VStack(spacing: 10) {
            tabBar
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // 切页签时内容轻微淡入下沉(微动效)
            Group {
                switch tab {
                case .system: LEDSystemPanelView()
                case .ai: LEDAIPanelView()
                case .skills: LEDSkillsPanelView()
                }
            }
            .id(tab)
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 5)))
        }
    }

    /// 页签栏:**只有选中态有胶囊**,未选中就是图标+文字裸在背景上。
    /// 两条从参考图学来的、之前做错过的要点:
    ///  1. 未选中**照样是白字**——"没有胶囊"不等于"变暗"。用灰字等于把它们做成了禁用态,读不清。
    ///  2. 间距要给足。挤在一起,整排还是会读成一个"分段控件",留白才是这个设计的一半。
    private var tabBar: some View {
        HStack(spacing: 10) {
            ForEach(Tab.allCases) { t in
                let selected = tab == t
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { tab = t }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: t.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(t.rawValue)
                            .font(LED.display(11.5, selected ? .bold : .medium))
                    }
                    // 选中:近黑字压在实色灯面上(真 LED 的反差);未选中:白字裸在底上
                    .foregroundStyle(selected ? LED.bg : LED.text)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, selected ? 13 : 2).padding(.vertical, 6)
                    .background {
                        if selected {
                            // 胶囊在页签间滑动,并沿途换成该页签的 LED 色
                            Capsule()
                                .fill(t.tint)
                                .shadow(color: t.tint.opacity(0.5), radius: 8)
                                .matchedGeometryEffect(id: "led.tab.chrome", in: tabNS)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gauge").font(.system(size: 9))
                    Text("活动监视器").font(LED.mono(9))
                }
                .foregroundStyle(LED.dim)
            }
            .buttonStyle(.plain)

            Spacer()

            if let t = usage.lastScan {
                HStack(spacing: 4) {
                    LEDCaption(text: "DATA", tint: LED.faint, size: 8)
                    Text(t.formatted(date: .omitted, time: .shortened))
                        .font(LED.mono(8))
                        .foregroundStyle(LED.faint)
                }
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power").font(.system(size: 9))
                    Text("退出").font(LED.mono(9))
                }
                .foregroundStyle(LED.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 呼吸指示灯(LED 版是圆灯珠;HUD 的方灯是另一套语言)

private struct LEDBreathDot: View {
    var color: Color = LED.green
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.9), radius: 4)
            .shadow(color: color.opacity(0.4), radius: 8)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}
