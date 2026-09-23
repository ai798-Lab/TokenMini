import SwiftUI

/// A single label and geometry contract for all five dashboard actions, including Menu.
struct DashboardToolbarLabel: View {
    let title: String
    let icon: String
    var selected = false
    @ObservedObject private var settings = DisplaySettings.shared

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(selected ? (settings.isDarkSkin ? Color.black : Color.white)
                         : (settings.isPrism ? Prism.silver : (settings.isDarkSkin ? Color.white : Color.primary)))
        .lineLimit(1)
        .fixedSize()
        .contentShape(Rectangle())
    }
}

struct DashboardToolbarChrome: ViewModifier {
    var selected = false
    var pressed = false
    @ObservedObject private var settings = DisplaySettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled
    @State private var mouse: CGPoint?
    private var hovering: Bool { isEnabled && mouse != nil }

    private var fill: Color {
        if selected { return themeAccent() }
        if settings.isPrism { return hovering ? Prism.panelHi : Prism.panel }
        return Color.primary.opacity(hovering ? 0.10 : 0.04)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .contentShape(Rectangle())
            .background(fill, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(selected ? themeAccent() : (settings.isPrism ? Prism.line : Color.primary.opacity(0.2)), lineWidth: 1))
            .overlay {
                if settings.isDarkSkin {
                    SweepBorder(shape: RoundedRectangle(cornerRadius: 5),
                                color: selected ? .white : themeAccent(), lineWidth: 1.5, radius: 32,
                                drive: .follow(isEnabled ? mouse : nil))
                }
            }
            .mouseSpotlight(color: settings.isDarkSkin && isEnabled && !reduceTransparency ? .white : nil,
                            at: mouse, radius: 60, intensity: selected ? 0.16 : 0.10,
                            clip: RoundedRectangle(cornerRadius: 5))
            .opacity(pressed ? 0.72 : 1)
            .trackingMouse($mouse)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

struct DashboardToolbarButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(DashboardToolbarChrome(selected: selected, pressed: configuration.isPressed))
    }
}

struct DashboardAppearanceChrome: ViewModifier {
    let unified: Bool
    @ObservedObject private var settings = DisplaySettings.shared
    func body(content: Content) -> some View {
        if unified {
            content.menuStyle(.button).buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .tint(settings.isPrism ? Prism.silver : (settings.isDarkSkin ? .white : .primary))
                .modifier(DashboardToolbarChrome())
        } else {
            content.menuStyle(.borderlessButton).modifier(ThemedMenuChrome())
        }
    }
}
