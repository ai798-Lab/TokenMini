import SwiftUI

/// Explicit selection styling prevents native checkbox/focus blue from leaking into dark skins.
struct ThemedCheckToggleStyle: ToggleStyle {
    @ObservedObject private var settings = DisplaySettings.shared
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if settings.isPrism {
            PrismSecondaryToggleStyle().makeBody(configuration: configuration)
        } else {
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
    @State private var prismFocused = false
    @ObservedObject private var settings = DisplaySettings.shared
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            if settings.isPrism {
                PrismEntryField(placeholder: title, text: $text, focused: $prismFocused).frame(height: 18)
            } else {
                TextField(title, text: $text).textFieldStyle(.plain).focused($focused).tint(themeAccent())
            }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("清除搜索")
            }
        }
        .font(.system(size: 12)).padding(9)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder((settings.isPrism ? prismFocused : focused) ? themeAccent().opacity(0.7) : Color.primary.opacity(0.18)))
    }
}

/// Small action menus share the same Prism panel instead of a blue native selection strip.
struct ThemedActionMenu: View {
    let title: String
    let actions: [(String, () -> Void)]
    @State private var presented = false
    @ObservedObject private var settings = DisplaySettings.shared
    var body: some View {
        if settings.isPrism {
            Button { presented.toggle() } label: { ThemedMenuLabel(title: title) }
                .buttonStyle(.plain).modifier(ThemedMenuChrome())
                .popover(isPresented: $presented, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Prism.secondary).padding(8)
                        ForEach(actions.indices, id: \.self) { index in
                            Button { presented = false; actions[index].1() } label: {
                                Text(actions[index].0).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(PrismButtonStyle())
                        }
                    }.padding(10).frame(width: 210).background(Prism.panel)
                        .tint(Prism.mint).preferredColorScheme(.dark)
                }
        } else {
            Menu {
                ForEach(actions.indices, id: \.self) { index in
                    Button(actions[index].0, action: actions[index].1)
                }
            } label: { ThemedMenuLabel(title: title) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).controlSize(.small)
        }
    }
}
