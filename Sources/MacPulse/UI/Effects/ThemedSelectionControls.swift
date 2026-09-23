import SwiftUI

/// Explicit selection styling prevents native checkbox/focus blue from leaking into dark skins.
struct ThemedCheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 9) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(configuration.isOn ? themeAccent() : Color.secondary)
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(configuration.isOn ? "已选" : "未选"))
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

struct ThemedChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ObservedObject private var settings = DisplaySettings.shared
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? themeAccent() : Color.secondary)
                Text(title).foregroundStyle(settings.isPrism ? Prism.silver : .primary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .padding(9)
            .background(selected ? themeAccent().opacity(0.10) : .clear,
                        in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ThemedSearchField: View {
    let title: String
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(title, text: $text).textFieldStyle(.plain).focused($focused)
                .tint(themeAccent())
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("清除搜索")
            }
        }
        .font(.system(size: 12)).padding(9)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(focused ? themeAccent().opacity(0.7) : Color.primary.opacity(0.18)))
    }
}
