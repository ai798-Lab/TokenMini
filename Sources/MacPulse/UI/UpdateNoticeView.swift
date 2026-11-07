import SwiftUI

/// Pinned above each popover's main scroll area. Sparkle owns the actual update flow.
struct UpdateNoticeView: View {
    @ObservedObject private var updates = UpdateController.shared
    @ObservedObject private var settings = DisplaySettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var showsFullNotes = false
    @AccessibilityFocusState private var undoFocused: Bool

    private var accent: Color { themeAccent() }
    private var textColor: Color { settings.isDarkSkin ? Prism.silver : .primary }
    private var secondaryColor: Color { settings.isDarkSkin ? Prism.secondary : .secondary }
    private var panelColor: Color { settings.isDarkSkin ? Prism.panel : Color.primary.opacity(0.035) }
    private var borderColor: Color { settings.isDarkSkin ? Prism.line : Color.primary.opacity(0.15) }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.22) }

    var body: some View {
        if updates.available != nil || updates.skippedUpdate != nil {
            content
        }
    }

    private var content: some View {
        Group {
            if let update = updates.available {
                VStack(alignment: .leading, spacing: 0) {
                    updateBar(update)
                    if expanded {
                        notes(update)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .background(panelColor, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(borderColor))
                .clipped()
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.text("新版本更新"))
            } else if let skipped = updates.skippedUpdate {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("已跳过此版本"))
                        Text(verbatim: skipped.version)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryColor)
                    Spacer(minLength: 4)
                    Button(L10n.text("撤销")) {
                        withAnimation(motion) { updates.restoreSkippedVersion() }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textColor)
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                    .accessibilityFocused($undoFocused)
                    .help(L10n.text("恢复此版本的更新提醒"))
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(panelColor, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(borderColor))
            }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: updates.available?.build) { _, _ in
            expanded = false
            showsFullNotes = false
        }
    }

    private func updateBar(_ update: AvailableUpdate) -> some View {
        HStack(spacing: 8) {
            Button(action: toggleNotes) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 26)
                        .background(accent.opacity(0.10), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("新版本可用"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(textColor)
                        Text(verbatim: update.version)
                            .font(.system(size: 11))
                            .foregroundStyle(secondaryColor)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? L10n.text("已展开") : L10n.text("已收起"))
            .accessibilityHint(L10n.text("显示或收起更新说明"))

            Button(action: toggleNotes) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Text(expanded ? L10n.text("收起") : L10n.text("查看说明"))
                            .fixedSize()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .font(.system(size: 11, weight: .medium))
                .frame(minWidth: 24, minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(secondaryColor)
            .accessibilityLabel(expanded ? L10n.text("收起更新说明") : L10n.text("查看更新说明"))
            .accessibilityValue(expanded ? L10n.text("已展开") : L10n.text("已收起"))
            .help(expanded ? L10n.text("收起更新说明") : L10n.text("查看更新说明"))

            Button { updates.checkForUpdates() } label: {
                Text(L10n.text("更新…"))
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .foregroundStyle(settings.isDarkSkin ? Prism.bg : Color.white)
                    .background(accent.opacity(updates.canCheckForUpdates ? 1 : 0.45),
                                in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(!updates.canCheckForUpdates)
            .help(L10n.text("打开更新窗口，查看下载和安装选项"))
        }
        .padding(10)
    }

    private func notes(_ update: AvailableUpdate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(borderColor).frame(height: 1)
            Text(showsFullNotes ? L10n.text("完整更新说明") : L10n.text("本次更新"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
            if !AppLanguage.current.rawValue.hasPrefix("zh") {
                Text(L10n.text("更新说明按发布者提供的原文显示。"))
                    .font(.system(size: 10)).foregroundStyle(secondaryColor)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if showsFullNotes {
                        Text(verbatim: update.notes)
                            .textSelection(.enabled)
                    } else {
                        ForEach(Array(update.highlights.enumerated()), id: \.offset) { _, highlight in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundStyle(accent.opacity(0.7))
                                Text(verbatim: highlight).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .font(.system(size: 12)).lineSpacing(4)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: showsFullNotes ? 180 : 125)
            HStack(alignment: .center, spacing: 8) {
                Button(showsFullNotes ? L10n.text("返回摘要") : L10n.text("完整更新说明")) {
                    withAnimation(motion) { showsFullNotes.toggle() }
                }
                Spacer(minLength: 0)
                Button(L10n.text("跳过此版本")) {
                    withAnimation(motion) {
                        expanded = false
                        showsFullNotes = false
                        updates.skipVersion()
                    }
                    undoFocused = true
                }
                .help(L10n.text("不再提醒此版本；下个版本仍会提醒"))
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(secondaryColor)
            .padding(.vertical, 5)
        }
        .padding(.horizontal, 12).padding(.bottom, 10)
    }

    private func toggleNotes() {
        withAnimation(motion) { expanded.toggle() }
    }
}
