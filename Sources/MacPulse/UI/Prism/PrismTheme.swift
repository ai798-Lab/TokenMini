import SwiftUI
import AppKit

/// Prism is an original material system, inspired by cinematic broadcast design.
/// Decoration is static in the app: monitoring should never require an idle render loop.
enum Prism {
    static let bg = Color(red: 0.031, green: 0.047, blue: 0.051)
    static let panel = Color(red: 0.067, green: 0.090, blue: 0.094)
    static let panelHi = Color(red: 0.102, green: 0.137, blue: 0.141)
    static let mint = Color(red: 0.78, green: 1.00, blue: 0.25)
    static let silver = Color(red: 0.88, green: 0.94, blue: 0.92)
    static let secondary = Color(red: 0.64, green: 0.72, blue: 0.69)
    static let core: NSImage? = Bundle.main.url(forResource: "PrismCore", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }
}

struct PrismSurface: ViewModifier {
    var accent: Color = Prism.mint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var mouse: CGPoint?
    private var hover: Bool { mouse != nil }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        content
            .background {
                shape.fill(Prism.panel)
                if !reduceTransparency {
                    shape.fill(LinearGradient(colors: [.white.opacity(hover ? 0.065 : 0.035), .clear],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [Prism.silver.opacity(hover ? 0.35 : 0.19),
                    .white.opacity(0.04), accent.opacity(0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .overlay {
                SweepBorder(shape: shape, color: accent, lineWidth: 1.5, drive: .follow(mouse))
            }
            .mouseSpotlight(color: accent, at: mouse, radius: 170, intensity: 0.15, clip: shape)
            .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hover)
            .trackingMouse($mouse)
    }
}

struct PrismArtwork: View {
    var body: some View {
        if let image = Prism.core {
            Image(nsImage: image).resizable().scaledToFill().accessibilityHidden(true)
        }
    }
}

struct PrismDashboardBanner: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("PRISM / 光核").font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2.5).foregroundStyle(Prism.mint)
                Text("每一份消耗，都清晰可见。")
                    .font(.system(size: 25, weight: .semibold)).foregroundStyle(Prism.silver)
                Text("AI 用量 · 额度 · Mac 状态")
                    .font(.system(size: 12)).foregroundStyle(Prism.secondary)
            }
            Spacer(minLength: 220)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(alignment: .trailing) {
            PrismArtwork().frame(width: 340, height: 200).clipped()
                .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing))
        }
        .background(Prism.bg)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

struct PrismPopoverView: View {
    @EnvironmentObject private var usage: UsageStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = DisplaySettings.shared
    @State private var page: Page = .overview
    enum Page: String, CaseIterable { case overview = "总览", system = "系统", ai = "AI 用量", skills = "Skills" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                BrandMark()
                Text("TokenMini").font(.system(size: 15, weight: .semibold)).foregroundStyle(Prism.silver)
                Spacer()
                Text("PRISM").font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2).foregroundStyle(Prism.secondary)
                DisplaySettingsMenu().foregroundStyle(Prism.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            HStack(spacing: 4) {
                ForEach(Page.allCases, id: \.self) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { page = item }
                    } label: {
                        Text(item.rawValue).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(page == item ? Prism.bg : Prism.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(page == item ? Prism.mint : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }.padding(4).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 14).padding(.bottom, 12)
            HUDScrollView(accent: Prism.mint) {
                VStack(spacing: 12) {
                    switch page {
                    case .overview:
                        tokenHero
                        HUDSimpleHomeView()
                    case .system: HUDSystemPanelView()
                    case .ai: HUDAIPanelView()
                    case .skills: HUDSkillsPanelView()
                    }
                }
                .padding(.horizontal, page == .overview ? 14 : 0)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 10) {
                Button { openWindow(id: "dashboard") } label: {
                    HStack {
                        Image(systemName: "chart.xyaxis.line")
                        Text("打开完整监控台")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 13).padding(.vertical, 11)
                    .foregroundStyle(Prism.bg).background(Prism.mint, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(PressableButtonStyle())
                HStack {
                    Text(usage.scanning ? "正在更新本地数据…" : usage.lastScan.map { "更新于 \($0.formatted(date: .omitted, time: .shortened))" } ?? "等待本地数据")
                    Spacer()
                    Button("退出") { NSApp.terminate(nil) }.buttonStyle(.plain)
                }.font(.system(size: 10)).foregroundStyle(Prism.secondary)
            }.padding(14).background(Prism.bg)
        }
        .frame(width: 360, height: 620)
        .background(Prism.bg)
        .preferredColorScheme(.dark).tint(Prism.mint)
    }

    private var tokenHero: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TODAY / 今日 Token")
                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Prism.secondary)
            Text(usage.lastScan == nil ? "—" : settings.tokens(usage.today.totalTokens))
                .font(.system(size: 33, weight: .medium, design: .rounded))
                .monospacedDigit().foregroundStyle(Prism.silver)
                .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.65)
            Text("输入、输出与缓存的合计")
                .font(.system(size: 10)).foregroundStyle(Prism.secondary)
        }
        .padding(17).frame(maxWidth: .infinity, minHeight: 123, alignment: .leading)
        .background(alignment: .trailing) {
            PrismArtwork().frame(width: 170, height: 123).clipped().opacity(0.90)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
        }
        .background(Prism.bg)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.17), lineWidth: 1))
    }
}
