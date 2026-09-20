import AppKit
import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var leaderboard: LeaderboardStore
    @ObservedObject private var settings = DisplaySettings.shared
    @State private var confirmLeave = false

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            ScrollView {
                VStack(spacing: 14) {
                    if let message = leaderboard.message { messageBar(message) }
                    membershipCard
                    rankingCard
                }
                .padding(18)
            }
            .background(contentBackground)
        }
        .frame(minWidth: 580, minHeight: 600)
        .background(baseBackground)
        .preferredColorScheme(settings.isDarkSkin ? .dark : nil)
        .tint(accent)
        .task(id: leaderboard.metric) { await leaderboard.load() }
        .onAppear { bringToFront() }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .alert("退出排行榜？", isPresented: $confirmLeave) {
            Button("取消", role: .cancel) {}
            Button("退出并删除榜单数据", role: .destructive) {
                Task { await leaderboard.leave() }
            }
        } message: {
            Text("退出后会停止同步并删除公开排行榜数据；TokenMini 的全部本地监控功能仍可正常使用。")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(leaderboard.isJoined ? success : muted).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text("社区排行")
                    .font(titleFont)
                    .foregroundStyle(primary)
                Text(leaderboard.isJoined ? "已加入 · 每日汇总自动同步" : "无需登录也能浏览")
                    .font(captionFont)
                    .foregroundStyle(muted)
            }
            Spacer()
            Button("网页榜单") { NSWorkspace.shared.open(AppInfo.rankings) }
                .buttonStyle(.plain)
                .font(captionFont)
                .foregroundStyle(accent)
            ThemedSegmented(
                items: RankingMetric.allCases.map { ($0, $0.label) },
                selection: $leaderboard.metric, size: 9)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(baseBackground.opacity(0.97))
    }

    private var membershipCard: some View {
        GlassCard {
            if leaderboard.isJoined {
                joinedContent
            } else {
                joinContent
            }
        }
    }

    private var joinContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("登录后自动加入", systemImage: "person.crop.circle.badge.plus")
                    .font(sectionFont)
                    .foregroundStyle(primary)
                Spacer()
                Text("默认打码")
                    .font(captionFont)
                    .foregroundStyle(accent)
            }
            Text("Google 登录成功后直接加入 Token 与 API 等价费用两个榜单。只同步上海时区每日总量、价格表版本和 App 版本；不上传会话正文、项目名、路径、模型明细或 AI 凭证。")
                .font(bodyFont)
                .foregroundStyle(muted)
                .lineSpacing(3)
            HStack {
                primaryJoinButton
                if leaderboard.signingIn { ProgressView().controlSize(.small) }
                Spacer()
                Text("不登录不影响任何本地功能")
                    .font(captionFont)
                    .foregroundStyle(faint)
            }
        }
    }

    @ViewBuilder
    private var primaryJoinButton: some View {
        if settings.isHUD {
            Button(leaderboard.signingIn ? "正在登录…" : "使用 Google 登录并加入") {
                Task { await leaderboard.signInAndJoin() }
            }
            .buttonStyle(HUDButtonStyle(size: 11))
            .disabled(leaderboard.signingIn)
        } else if settings.isLED {
            Button(leaderboard.signingIn ? "正在登录…" : "使用 Google 登录并加入") {
                Task { await leaderboard.signInAndJoin() }
            }
            .buttonStyle(LEDGhostButtonStyle(size: 11, prominent: true))
            .disabled(leaderboard.signingIn)
        } else {
            Button(leaderboard.signingIn ? "正在登录…" : "使用 Google 登录并加入") {
                Task { await leaderboard.signInAndJoin() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(leaderboard.signingIn)
        }
    }

    private var joinedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(leaderboard.profile?.displayedName ?? "已加入")
                        .font(sectionFont).foregroundStyle(primary)
                    Text("本周 · UTC+8")
                        .font(captionFont).foregroundStyle(muted)
                }
                Spacer()
                if leaderboard.syncing {
                    Label("同步中", systemImage: "arrow.triangle.2.circlepath")
                        .font(captionFont).foregroundStyle(accent)
                } else if let date = leaderboard.lastSyncAt {
                    Text("同步于 " + date.formatted(date: .omitted, time: .shortened))
                        .font(captionFont).foregroundStyle(faint)
                }
            }
            HStack(spacing: 10) {
                standing("Token 名次", leaderboard.me?.tokens, metric: .tokens)
                standing("费用名次", leaderboard.me?.cost, metric: .cost)
            }
            Toggle(isOn: Binding(
                get: { leaderboard.profile?.displayMode == "public" },
                set: { value in Task { await leaderboard.setPublicName(value) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("公开显示完整昵称").font(bodyFont).foregroundStyle(primary)
                    Text("关闭时只保留昵称最后一个字，例如 ＊＊＊平")
                        .font(captionFont).foregroundStyle(muted)
                }
            }
            .toggleStyle(.switch)
            HStack {
                Button("立即同步") { Task { await leaderboard.syncIfNeeded(force: true) } }
                    .buttonStyle(.plain).font(captionFont).foregroundStyle(accent)
                Spacer()
                Button("退出排行榜", role: .destructive) { confirmLeave = true }
                    .buttonStyle(.plain).font(captionFont).foregroundStyle(danger)
            }
        }
    }

    private func standing(
        _ title: String,
        _ value: RankingStanding?,
        metric: RankingMetric
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(captionFont).foregroundStyle(muted)
            Text(value?.rank.map { "#\($0)" } ?? "暂未上榜")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(value?.rank == nil ? muted : accent)
            Text(format(value?.value ?? 0, metric: metric))
                .font(captionFont).foregroundStyle(faint)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var rankingCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text(leaderboard.metric.label + " · 本周")
                        .font(sectionFont).foregroundStyle(primary)
                    Spacer()
                    Text("TOP 100").font(captionFont).foregroundStyle(faint)
                }
                .padding(15)
                Divider().opacity(settings.isDarkSkin ? 0.2 : 1)
                if leaderboard.loading {
                    stateView("正在读取榜单…", progress: true)
                } else if let error = leaderboard.rankingError {
                    rankingErrorView(error)
                } else if let entries = leaderboard.ranking?.entries, !entries.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            rankingRow(entry)
                            if entry.id != entries.last?.id { Divider().opacity(settings.isDarkSkin ? 0.12 : 0.55) }
                        }
                    }
                } else {
                    stateView("还没有人上榜。登录后你可以成为第一位。", progress: false)
                }
                if leaderboard.metric == .cost {
                    Text("费用为按公开模型价格计算的 API 等价预估，不代表订阅实际扣款。")
                        .font(captionFont).foregroundStyle(faint)
                        .padding(.horizontal, 15).padding(.bottom, 14)
                }
            }
        }
    }

    private func rankingRow(_ entry: RankingEntry) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", entry.rank))
                .font(rankFont).foregroundStyle(entry.rank <= 3 ? accent : muted)
                .frame(width: 32, alignment: .leading)
            Text(entry.name)
                .font(bodyFont).fontWeight(entry.rank <= 3 ? .semibold : .regular)
                .foregroundStyle(primary).lineLimit(1)
            Spacer()
            Text(format(entry.value, metric: leaderboard.metric))
                .font(rankFont).foregroundStyle(entry.rank <= 3 ? accent : primary)
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(entry.rank) 名，\(entry.name)，\(format(entry.value, metric: leaderboard.metric))")
    }

    private func stateView(_ text: String, progress: Bool) -> some View {
        HStack(spacing: 9) {
            if progress { ProgressView().controlSize(.small) }
            Text(text).font(bodyFont).foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func rankingErrorView(_ text: String) -> some View {
        VStack(spacing: 10) {
            Text(text).font(bodyFont).foregroundStyle(muted)
            Button("重新加载") { Task { await leaderboard.load() } }
                .buttonStyle(.plain).font(captionFont).foregroundStyle(accent)
            Text("本地监控不受影响")
                .font(captionFont).foregroundStyle(faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private func messageBar(_ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(warning)
            Text(text).font(bodyFont).foregroundStyle(primary)
            Spacer()
            Button { leaderboard.message = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(muted)
        }
        .padding(11)
        .background(warning.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(warning.opacity(0.28)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func format(_ value: Int64, metric: RankingMetric) -> String {
        metric == .tokens
            ? settings.tokens(Int(clamping: value))
            : settings.currencyStr(Double(value) / 1_000_000)
    }

    private func bringToFront() {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let window = NSApp.windows.first {
                $0.identifier?.rawValue == "leaderboard" || $0.title == "社区排行"
            }
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }

    private var accent: Color { settings.isLED ? LED.amber : (settings.isHUD ? HUD.cyan : .accentColor) }
    private var success: Color { settings.isLED ? LED.green : (settings.isHUD ? HUD.green : .green) }
    private var danger: Color { settings.isLED ? LED.red : (settings.isHUD ? HUD.red : .red) }
    private var warning: Color { settings.isLED ? LED.amber : (settings.isHUD ? HUD.amber : .orange) }
    private var primary: Color { settings.isLED ? LED.text : (settings.isHUD ? HUD.text : .primary) }
    private var muted: Color { settings.isLED ? LED.dim : (settings.isHUD ? HUD.dim : .secondary) }
    private var faint: Color { settings.isLED ? LED.faint : (settings.isHUD ? HUD.faint : .secondary.opacity(0.75)) }
    private var baseBackground: Color { settings.isLED ? LED.bg : (settings.isHUD ? HUD.bg : Color(nsColor: .windowBackgroundColor)) }
    private var titleFont: Font { settings.isLED ? LED.display(18, .bold) : (settings.isHUD ? HUD.mono(17, .bold) : .title2.bold()) }
    private var sectionFont: Font { settings.isLED ? LED.display(13, .bold) : (settings.isHUD ? HUD.mono(12, .bold) : .headline) }
    private var bodyFont: Font { settings.isLED ? LED.display(11, .medium) : (settings.isHUD ? HUD.mono(10) : .body) }
    private var captionFont: Font { settings.isLED ? LED.mono(9) : (settings.isHUD ? HUD.mono(8.5) : .caption) }
    private var rankFont: Font { settings.isLED ? LED.mono(12, .bold) : (settings.isHUD ? HUD.mono(11, .bold) : .system(size: 12, weight: .semibold, design: .monospaced)) }

    @ViewBuilder private var divider: some View {
        if settings.isDarkSkin {
            ZStack(alignment: .leading) {
                Rectangle().fill(accent.opacity(0.12)).frame(height: 1)
                Rectangle().fill(accent.opacity(0.85)).frame(width: 96, height: 1)
            }
        } else { Divider() }
    }

    @ViewBuilder private var contentBackground: some View {
        if settings.isLED {
            ZStack { LED.bg; LEDDotMatrix(tint: LED.amber, pitch: 6, alpha: 0.04) }
        } else if settings.isHUD {
            ZStack { HUD.bg; HUDGridBackground() }
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
