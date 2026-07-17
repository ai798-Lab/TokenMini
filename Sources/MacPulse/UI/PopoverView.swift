import SwiftUI
import AppKit

/// 点击菜单栏后的主面板入口:按主题分发到经典 / HUD / LED 三套视图树。
/// HUDWindowShaper 负责窗体外框:仅 HUD 把系统圆角遮罩换成切角(LED 是 iOS 味圆角,保留系统形状)。
struct PopoverView: View {
    @ObservedObject private var settings = DisplaySettings.shared
    @EnvironmentObject private var system: SystemMonitor
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var quota: QuotaStore
    @AppStorage("macpulse.onboardingCompleted") private var onboardingCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if onboardingCompleted {
                switch settings.theme {
                case .hud: HUDPopoverView()
                case .led: LEDPopoverView()
                case .classic: ClassicPopoverView()
                }
            } else {
                FirstRunPrivacyView {
                    onboardingCompleted = true
                    usage.start()
                    quota.start()
                    VibeMoments.shared.start(system: system, usage: usage)
                }
            }
        }
        .background(HUDWindowShaper(active: settings.isHUD))
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
    }
}

/// HUD 主题主面板:深空底 + 顶部指挥舱标头 + 切角页签。
struct HUDPopoverView: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var usage: UsageStore
    @AppStorage("macpulse.proMode") private var proMode = false
    @State private var tab: Tab = .system
    @State private var sweepX: CGFloat = 0
    @State private var sweepAlpha: Double = 0
    @Namespace private var tabNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Tab: String, CaseIterable, Identifiable {
        case system = "系统"
        case ai = "AI 用量"
        case skills = "Skills"
        var id: String { rawValue }
        /// 页签的 FUI 代号
        var code: String {
            switch self {
            case .system: return "01/SYS"
            case .ai: return "02/AI"
            case .skills: return "03/SKL"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            accentDivider
            // 窗口尺寸定死(否则 MenuBarExtra(.window) 随内容重排,切换瞬间圆角闪失),超高内容滚动。
            HUDScrollView {
                Group {
                    if proMode {
                        proContent
                    } else {
                        HUDSimpleHomeView()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            Rectangle().fill(HUD.gridline).frame(height: 1)
            footer
        }
        .frame(width: 340, height: 560)
        .background(HUD.bg)
        // 窗体外形:顶部方角、底部双切角,配一圈发丝描边(系统 material 遮罩由 HUDWindowShaper 同步)
        .clipShape(CutCorner(cut: 14, corners: [.bottomLeft, .bottomRight]))
        .overlay {
            CutCorner(cut: 14, corners: [.bottomLeft, .bottomRight])
                .stroke(HUD.cyan.opacity(0.22), lineWidth: 1)
        }
        .tint(HUD.cyan)
        .preferredColorScheme(.dark)
    }

    // MARK: 顶部指挥舱标头

    private var header: some View {
        HStack(spacing: 8) {
            HUDStatusDot(color: HUD.green, size: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text("MACPULSE")
                    .font(HUD.mono(12, .bold))
                    .kerning(2.5)
                    .foregroundStyle(HUD.text)
                Text(proMode ? "PRO.CONSOLE // 专业模式" : "SYS.MONITOR // 监控器")
                    .font(HUD.mono(7.5, .medium))
                    .kerning(1.2)
                    .foregroundStyle(HUD.faint)
            }
            Spacer()
            HUDClock()
            DisplaySettingsMenu()
                .foregroundStyle(HUD.dim)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { proMode.toggle() }
            } label: {
                Text(proMode ? "简单" : "专业")
            }
            .buttonStyle(HUDButtonStyle(size: 9))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10).padding(.bottom, 8)
    }

    /// 标头下的分割线:整条发丝线 + 左侧一段主色亮线;弹窗打开时一道扫描光划过(微动效)
    private var accentDivider: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(HUD.gridline).frame(height: 1)
            Rectangle().fill(HUD.cyan.opacity(0.8)).frame(width: 56, height: 1)
                .shadow(color: HUD.cyan.opacity(0.6), radius: 2)
            GeometryReader { geo in
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, HUD.cyan, .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 90, height: 1)
                    .offset(x: sweepX * (geo.size.width + 90) - 90)
                    .opacity(sweepAlpha)
                    .shadow(color: HUD.cyan.opacity(0.8), radius: 3)
            }
            .frame(height: 1)
            .allowsHitTesting(false)
        }
        .onAppear {
            guard !reduceMotion else { return }
            sweepX = 0
            sweepAlpha = 0.9
            withAnimation(.easeInOut(duration: 0.9).delay(0.1)) { sweepX = 1 }
            withAnimation(.easeOut(duration: 0.3).delay(0.8)) { sweepAlpha = 0 }
        }
    }

    private var proContent: some View {
        VStack(spacing: 8) {
            tabBar
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // 切页签时内容轻微淡入下沉(微动效)
            Group {
                switch tab {
                case .system: HUDSystemPanelView()
                case .ai: HUDAIPanelView()
                case .skills: HUDSkillsPanelView()
                }
            }
            .id(tab)
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 5)))
        }
    }

    /// 自定义切角页签栏(替代系统 segmented picker)
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                let selected = tab == t
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = t }
                } label: {
                    VStack(spacing: 3) {
                        Text(t.code)
                            .font(HUD.mono(7, .semibold))
                            .kerning(0.8)
                            .foregroundStyle(selected ? HUD.cyan.opacity(0.75) : HUD.faint)
                        Text(t.rawValue)
                            .font(.system(size: 11, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? HUD.text : HUD.dim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        if selected {
                            // matchedGeometryEffect:选中框在页签间滑动(微动效)
                            ZStack(alignment: .bottom) {
                                CutCorner(cut: 5).fill(HUD.cyan.opacity(0.10))
                                CutCorner(cut: 5).stroke(HUD.cyan.opacity(0.45), lineWidth: 1)
                                Rectangle().fill(HUD.cyan).frame(height: 2)
                                    .padding(.horizontal, 6)
                                    .shadow(color: HUD.cyan.opacity(0.8), radius: 3)
                            }
                            .matchedGeometryEffect(id: "hud.tab.chrome", in: tabNS)
                        } else {
                            CutCorner(cut: 5).fill(Color.white.opacity(0.03))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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
                    Text("活动监视器").font(HUD.mono(9))
                }
                .foregroundStyle(HUD.dim)
            }
            .buttonStyle(.plain)

            Spacer()

            if let t = usage.lastScan {
                Text("DATA \(t.formatted(date: .omitted, time: .shortened))")
                    .font(HUD.mono(8))
                    .kerning(0.6)
                    .foregroundStyle(HUD.faint)
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power").font(.system(size: 9))
                    Text("退出").font(HUD.mono(9))
                }
                .foregroundStyle(HUD.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
