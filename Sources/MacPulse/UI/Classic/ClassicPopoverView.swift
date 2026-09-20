import SwiftUI
import AppKit

/// 经典主题主面板(原版系统原生风):默认 = 简单模式首页;「专业模式」= 系统/AI 用量页签。
struct ClassicPopoverView: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var usage: UsageStore
    @AppStorage("macpulse.proMode") private var proMode = false
    @State private var tab: Tab = .system

    enum Tab: String, CaseIterable, Identifiable {
        case system = "系统"
        case ai = "AI 用量"
        case skills = "Skills"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // 窗口尺寸定死(否则 MenuBarExtra(.window) 随内容重排,切换瞬间圆角闪失),超高内容滚动。
            ScrollView {
                Group {
                    if proMode {
                        proContent
                    } else {
                        ClassicSimpleHomeView()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            Divider()
            footer
        }
        .frame(width: 340, height: 560)
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark()
            Text("TokenMini")
                .font(.headline)
            Spacer()
            DisplaySettingsMenu()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { proMode.toggle() }
            } label: {
                Label(proMode ? "简单" : "专业", systemImage: proMode ? "circle.grid.2x2" : "slider.horizontal.3")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10).padding(.bottom, 8)
    }

    private var proContent: some View {
        VStack(spacing: 8) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in Text(t.rawValue).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 8)

            switch tab {
            case .system: ClassicSystemPanelView()
            case .ai: ClassicAIPanelView()
            case .skills: ClassicSkillsPanelView()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            } label: {
                Label("活动监视器", systemImage: "gauge")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            if let t = usage.lastScan {
                Text("AI 数据 \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
