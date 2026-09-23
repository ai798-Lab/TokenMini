import SwiftUI

struct FirstRunPrivacyView: View {
    @EnvironmentObject private var quota: QuotaStore
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HUDStatusDot(color: HUD.cyan, size: 7)
                Text("TOKENMINI // FIRST RUN")
                    .font(HUD.mono(10, .bold))
                    .kerning(1.4)
                    .foregroundStyle(HUD.cyan)
                Spacer()
                Text(AppInfo.version).font(HUD.mono(8)).foregroundStyle(HUD.faint)
            }
            .padding(.bottom, 17)

            Text("数据先留在你的 Mac。")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(HUD.text)
            Text("继续前，请先了解 TokenMini 会读取什么、不会做什么。")
                .font(.system(size: 12.5))
                .foregroundStyle(HUD.dim)
                .lineSpacing(4)
                .padding(.top, 8)

            VStack(spacing: 10) {
                notice("doc.text.magnifyingglass", "本地会话统计",
                       "只读扫描 Claude Code / Codex JSONL；会话正文不上传。")
                notice("hand.raised", "默认不上传",
                       "不接入分析或广告；只有主动登录排行榜后才同步每日汇总。")
                notice("dollarsign.circle", "费用是等价预估",
                       "按 token 与公开价格计算，不代表订阅实际扣款。")
                notice("trash.slash", "清理需要再次确认",
                       "只展示可再生缓存；删除前仍会经过路径安全守卫。")
            }
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { quota.claudeAccessEnabled },
                    set: { quota.setClaudeAccessEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("启用 Claude 额度（实验）")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(HUD.text)
                        Text("默认关闭；开启前会再次确认读取账号凭证并联网查询额度")
                            .font(.system(size: 9.5))
                            .foregroundStyle(HUD.faint)
                    }
                }
                .toggleStyle(.switch)
                Text("通知默认关闭，可稍后在设置中主动开启。")
                    .font(HUD.mono(8))
                    .foregroundStyle(HUD.faint)
            }
            .padding(13)
            .background(HUD.panel)
            .overlay(CutCorner(cut: 7).stroke(HUD.gridline, lineWidth: 1))
            .clipShape(CutCorner(cut: 7))
            .padding(.top, 18)

            Spacer()

            HStack {
                Button("隐私说明") { NSWorkspace.shared.open(AppInfo.privacy) }
                    .buttonStyle(.plain)
                    .font(HUD.mono(9))
                    .foregroundStyle(HUD.dim)
                Spacer()
                Button("开始使用") { onContinue() }
                    .buttonStyle(HUDButtonStyle(size: 11))
            }
        }
        .padding(20)
        .frame(width: 340, height: 560)
        .background(HUD.bg)
        .preferredColorScheme(.dark)
    }

    private func notice(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(HUD.cyan)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(HUD.text)
                Text(body).font(.system(size: 10)).foregroundStyle(HUD.dim).lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
