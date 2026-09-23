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
        .padding(.horizontal, 12)
        .frame(height: 30)
        .contentShape(Rectangle())
    }
}

struct DashboardToolbarChrome: ViewModifier {
    var selected = false
    var pressed = false
    @ObservedObject private var settings = DisplaySettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var fill: Color {
        if selected { return themeAccent() }
        if settings.isPrism { return hovering ? Prism.panelHi : Prism.panel }
        return Color.primary.opacity(hovering ? 0.10 : 0.04)
    }

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(selected ? themeAccent() : (settings.isPrism ? Prism.line : Color.primary.opacity(0.2)), lineWidth: 1))
            .opacity(pressed ? 0.72 : 1)
            .onHover { hovering = $0 }
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
    func body(content: Content) -> some View {
        if unified {
            content.menuStyle(.button).buttonStyle(.plain)
                .modifier(DashboardToolbarChrome())
        } else {
            content.modifier(ThemedMenuChrome())
        }
    }
}
