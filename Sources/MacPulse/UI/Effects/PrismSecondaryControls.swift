import AppKit
import SwiftUI

/// Shared by secondary pages. Non-Prism appearances keep their native controls.
struct PrismSecondaryAction: ViewModifier {
    var prominent = false
    @ObservedObject private var settings = DisplaySettings.shared
    func body(content: Content) -> some View {
        if settings.isPrism {
            content.buttonStyle(PrismButtonStyle(prominent: prominent, size: 11))
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

struct PrismSecondaryPageChrome: ViewModifier {
    @ObservedObject private var settings = DisplaySettings.shared
    func body(content: Content) -> some View {
        if settings.isPrism {
            content.font(Prism.label(12)).foregroundStyle(Prism.silver)
                .buttonStyle(PrismButtonStyle(size: 11))
                .toggleStyle(PrismSecondaryToggleStyle())
                .disclosureGroupStyle(PrismSecondaryDisclosureStyle())
        } else { content }
    }
}

struct PrismSecondarySection: ViewModifier {
    @ObservedObject private var settings = DisplaySettings.shared
    func body(content: Content) -> some View {
        if settings.isPrism {
            content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(PrismSurface())
        } else { content }
    }
}

struct PrismSecondaryToggleStyle: ToggleStyle {
    var isSwitch = false
    @ObservedObject private var settings = DisplaySettings.shared
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if settings.isPrism {
            Button { configuration.isOn.toggle() } label: {
                HStack(spacing: 9) {
                    if !isSwitch { checkmark(configuration.isOn) }
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isSwitch {
                        Capsule().fill(configuration.isOn ? Prism.mint : Prism.line)
                            .frame(width: 32, height: 18)
                            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                                Circle().fill(configuration.isOn ? Prism.bg : Prism.secondary)
                                    .frame(width: 14, height: 14).padding(2)
                            }
                    }
                }
                .foregroundStyle(Prism.silver)
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isOn)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
            }
        } else if isSwitch {
            SwitchToggleStyle().makeBody(configuration: configuration)
        } else {
            CheckboxToggleStyle().makeBody(configuration: configuration)
        }
    }

    private func checkmark(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(on ? Prism.mint : Prism.bg)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(on ? Prism.mint : Prism.line))
            .overlay {
                if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Prism.bg) }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

private struct PrismSecondaryDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if reduceMotion { configuration.isExpanded.toggle() }
                else { withAnimation(.easeOut(duration: 0.15)) { configuration.isExpanded.toggle() } }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    configuration.label.font(Prism.label(11))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(configuration.isExpanded ? Prism.mint : Prism.secondary)
                .padding(.vertical, 5).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "已展开" : "已折叠")
            if configuration.isExpanded { configuration.content.padding(.leading, 22).padding(.top, 8) }
        }
    }
}

struct PrismSecondaryChoiceStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Prism.label(12)).foregroundStyle(selected ? Prism.mint : Prism.silver)
            .padding(.horizontal, 10).frame(minHeight: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Prism.mint.opacity(0.10) : (configuration.isPressed ? Prism.panelHi : .clear),
                        in: RoundedRectangle(cornerRadius: Prism.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Prism.controlRadius)
                .strokeBorder(selected ? Prism.mint.opacity(0.5) : .clear))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.4)
    }
}

/// Each Prism field owns its editor, so selection never flashes system blue and
/// changing themes cannot leak selection attributes into another native control.
struct PrismEntryField: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let placeholder: String
    @Binding var text: String
    @Binding var focused: Bool

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        let cell = PrismEntryCell(textCell: "")
        cell.editor.focusChanged = { [weak coordinator = context.coordinator] focused in
            DispatchQueue.main.async { coordinator?.parent.focused = focused }
        }
        field.cell = cell
        field.isEnabled = isEnabled
        field.isEditable = true; field.isSelectable = true
        cell.usesSingleLineMode = true; cell.wraps = false; cell.isScrollable = true
        field.isBordered = false; field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = NSColor(Prism.silver)
        field.placeholderAttributedString = NSAttributedString(string: placeholder,
            attributes: [.foregroundColor: NSColor(Prism.faint)])
        field.setAccessibilityLabel(placeholder)
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = isEnabled
        field.textColor = NSColor(isEnabled ? Prism.silver : Prism.faint)
        if field.stringValue != text { field.stringValue = text }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        (field.cell as? PrismEntryCell)?.editor.focusChanged = nil
        field.delegate = nil
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PrismEntryField
        init(_ parent: PrismEntryField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
    }
}

private final class PrismEntryEditor: NSTextView {
    var focusChanged: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged?(false) }
        return accepted
    }
}

private final class PrismEntryCell: NSTextFieldCell {
    let editor: PrismEntryEditor = {
        let editor = PrismEntryEditor()
        editor.isFieldEditor = true
        editor.isRichText = false
        return editor
    }()
    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let result = super.setUpFieldEditorAttributes(textObj)
        if let editor = result as? NSTextView {
            editor.selectedTextAttributes = [.backgroundColor: NSColor(Prism.mint).withAlphaComponent(0.25),
                                             .foregroundColor: NSColor(Prism.silver)]
            editor.insertionPointColor = NSColor(Prism.mint)
        }
        return result
    }
}

struct PrismSourceTextField: View {
    let placeholder: String
    @Binding var text: String
    @State private var focused = false
    var body: some View {
        PrismEntryField(placeholder: placeholder, text: $text, focused: $focused)
            .frame(height: 18).padding(9)
            .background(Prism.bg, in: RoundedRectangle(cornerRadius: Prism.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Prism.controlRadius)
                .strokeBorder(focused ? Prism.mint : Prism.line, lineWidth: 1))
    }
}
