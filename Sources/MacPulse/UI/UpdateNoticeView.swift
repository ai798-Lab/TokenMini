import SwiftUI

/// Lives inside the existing menu-bar popover. This view never presents a window.
struct UpdateNoticeView: View {
    @ObservedObject private var updates = UpdateController.shared
    @ObservedObject private var settings = DisplaySettings.shared
    @State private var expanded = false
    private var accent: Color { settings.isPrism ? Prism.mint : themeAccent() }

    var body: some View {
        if let update = updates.available {
            VStack(alignment: .leading, spacing: 12) {
                Button { expanded.toggle() } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("新版本可用").fontWeight(.semibold)
                        Spacer()
                        Text(expanded ? "收起" : "查看更新")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 11)).padding(10)
                    .foregroundStyle(settings.isDarkSkin ? Color.black : Color.white)
                    .background(accent, in: RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(.plain)
                if expanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TokenMini 有更新").font(.system(size: 19, weight: .bold))
                        Text("版本 \(update.version)").font(.caption).foregroundStyle(.secondary)
                        ScrollView {
                            Text(update.notes).font(.system(size: 12)).lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }.frame(maxHeight: 160)
                        HStack(spacing: 10) {
                            Button { updates.skipVersion(); expanded = false } label: {
                                Text("跳过此版本")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .foregroundStyle(.primary)
                                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15)))
                            }.buttonStyle(.plain)
                            Button { updates.checkForUpdates() } label: {
                                Label("下载更新", systemImage: "arrow.down.to.line")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .foregroundStyle(settings.isDarkSkin ? Color.black : Color.white)
                                    .background(accent, in: RoundedRectangle(cornerRadius: 4))
                            }.buttonStyle(.plain).disabled(!updates.canCheckForUpdates)
                        }
                    }.padding(12)
                    .background(settings.isPrism ? Prism.panel : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6))
                }
            }.padding(.horizontal, 14).padding(.top, 8)
        }
    }
}
