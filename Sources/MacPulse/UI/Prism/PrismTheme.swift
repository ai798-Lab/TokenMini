import SwiftUI
import AppKit

/// The website's paper / ink / signal palette is shared by every Prism component.
/// Artwork stays static; only direct control feedback animates.
enum Prism {
    static let bg = Color(red: 11/255, green: 13/255, blue: 12/255)
    static let panel = Color(red: 21/255, green: 26/255, blue: 22/255)
    static let panelHi = Color(red: 31/255, green: 38/255, blue: 30/255)
    static let mint = Color(red: 181/255, green: 255/255, blue: 57/255)
    static let silver = Color(red: 241/255, green: 241/255, blue: 233/255)
    static let secondary = Color(red: 183/255, green: 193/255, blue: 177/255)
    static let faint = Color(red: 154/255, green: 168/255, blue: 142/255)
    static let line = Color(red: 64/255, green: 75/255, blue: 57/255)
    static let radius: CGFloat = 6
    static let controlRadius: CGFloat = 4
    static func label(_ size: CGFloat = 11, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
    static let series: [Color] = [mint, silver,
        Color(red: 0.32, green: 0.76, blue: 0.60),
        Color(red: 0.62, green: 0.76, blue: 0.88),
        Color(red: 0.80, green: 0.72, blue: 0.46),
        Color(red: 0.62, green: 0.73, blue: 0.39)]
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
        let shape = RoundedRectangle(cornerRadius: Prism.radius, style: .continuous)
        content
            .background(hover ? Prism.panelHi : Prism.panel, in: shape)
            .overlay {
                shape.strokeBorder(hover ? accent.opacity(0.65) : Prism.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                Rectangle().fill(accent.opacity(hover ? 1 : 0.5)).frame(width: 28, height: 2)
                    .padding(.leading, 14).allowsHitTesting(false)
            }
            .overlay {
                SweepBorder(shape: shape, color: accent, lineWidth: 1.5, drive: .follow(mouse))
            }
            .mouseSpotlight(color: reduceTransparency ? nil : accent, at: mouse,
                            radius: 150, intensity: 0.10, clip: shape)
            .shadow(color: reduceTransparency ? .clear : .black.opacity(0.12), radius: 8, y: 3)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hover)
            .trackingMouse($mouse)
    }
}

/// A single geometry and state treatment for buttons, filters and selected tabs.
struct PrismControlChrome: ViewModifier {
    var active = false
    var accent: Color = Prism.mint
    var pressed = false
    var size: CGFloat = 11
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var mouse: CGPoint?
    private var hover: Bool { isEnabled && mouse != nil }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Prism.controlRadius)
        content
            .font(Prism.label(max(size, 10), active ? .bold : .medium))
            .foregroundStyle(active ? Prism.bg : (hover ? Prism.silver : Prism.secondary))
            .padding(.horizontal, 10).frame(minHeight: 28)
            .background(active ? accent : (hover ? Prism.panelHi : Prism.panel), in: shape)
            .overlay(shape.strokeBorder(active ? accent : (hover ? Prism.secondary : Prism.line), lineWidth: 1))
            .overlay {
                SweepBorder(shape: shape, color: active ? Prism.silver : accent,
                            lineWidth: 1.5, drive: .follow(isEnabled ? mouse : nil))
            }
            .mouseSpotlight(color: reduceTransparency || !isEnabled ? nil : Prism.silver,
                            at: mouse, radius: 55, intensity: active ? 0.16 : 0.10, clip: shape)
            .opacity(isEnabled ? (pressed ? 0.75 : 1) : 0.4)
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hover)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: pressed)
            .trackingMouse($mouse)
    }
}

struct PrismButtonStyle: ButtonStyle {
    var prominent = false
    var accent: Color = Prism.mint
    var size: CGFloat = 11
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(PrismControlChrome(active: prominent, accent: accent,
                                                       pressed: configuration.isPressed, size: size))
    }
}

struct PrismArtwork: View {
    var body: some View {
        if let image = Prism.core {
            Image(nsImage: image).resizable().scaledToFill().accessibilityHidden(true)
        }
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
                BrandLockup().foregroundStyle(Color(red: 24/255, green: 33/255, blue: 28/255))
                Spacer(minLength: 0)
                DisplaySettingsMenu().foregroundStyle(Prism.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 9).background(Prism.silver)
            ThemedSegmented(items: Page.allCases.map { ($0, $0.rawValue) }, selection: $page, size: 11)
                .padding(.horizontal, 14).padding(.vertical, 12)
            HUDScrollView(accent: Prism.mint) {
                VStack(spacing: 12) {
                    UpdateNoticeView()
                    switch page {
                    case .overview:
                        tokenHero
                        HUDSimpleHomeView().padding(.horizontal, 14)
                    case .system: HUDSystemPanelView()
                    case .ai: HUDAIPanelView()
                    case .skills: HUDSkillsPanelView()
                    }
                }
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
                    .foregroundStyle(Prism.bg).background(Prism.mint, in: RoundedRectangle(cornerRadius: Prism.controlRadius))
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
        PrismTokenHero(value: usage.lastScan == nil ? "—" : settings.tokens(usage.today.totalTokens))
    }
}
