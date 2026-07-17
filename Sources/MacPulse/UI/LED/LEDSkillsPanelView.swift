import SwiftUI

/// LED 主题·Skills 页签:查看/搜索 Claude Code 与 Codex 的已装 skill,
/// 支持 GitHub(owner/repo)与本地文件夹安装、卸载(进废纸篓)、跨工具复制。
/// 视觉基调绿(LED.green,与弹窗页签选中色呼应);功能/话术与 HUD·经典版逐字一致。
struct LEDSkillsPanelView: View {
    @EnvironmentObject var store: SkillManagerStore
    @State private var search = ""
    @State private var toolFilter: ToolFilter = .all
    @Namespace private var filterNS
    @State private var expanded: String?          // 展开的 skill id
    @State private var toUninstall: SkillInfo?
    @State private var repoInput = ""

    enum ToolFilter: String, CaseIterable, Identifiable {
        case all = "全部", claude = "Claude", codex = "Codex"
        var id: String { rawValue }
        func matches(_ s: SkillInfo) -> Bool {
            switch self {
            case .all: return true
            case .claude: return s.tool == .claude
            case .codex: return s.tool == .codex
            }
        }
    }

    private var filtered: [SkillInfo] {
        store.skills.filter { s in
            guard toolFilter.matches(s) else { return false }
            guard !search.isEmpty else { return true }
            return s.name.localizedCaseInsensitiveContains(search)
                || s.description.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statsRow
            controls
            skillList
            installSection
            if let msg = store.lastMessage {
                Text(msg).font(LED.mono(8)).foregroundStyle(LED.dim)
                    .lineLimit(2)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear { if store.skills.isEmpty { store.refresh() } }
        .alert("卸载 Skill", isPresented: Binding(
            get: { toUninstall != nil }, set: { if !$0 { toUninstall = nil } })) {
            Button("取消", role: .cancel) { toUninstall = nil }
            Button("移到废纸篓", role: .destructive) {
                if let s = toUninstall { store.uninstall(s) }
                toUninstall = nil
            }
        } message: {
            if let s = toUninstall {
                Text("将把「\(s.name)」的整个文件夹移到废纸篓(可从废纸篓恢复)。")
            }
        }
        .sheet(item: $store.pendingInstall) { pending in
            LEDMultiSkillPicker(pending: pending, store: store)
        }
    }

    // MARK: 统计(整块 LED 显示屏:两个数码管读数 = 两个工具的装机量)

    private var statsRow: some View {
        LEDPanel(tint: LED.green, padding: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    LEDCaption(text: "SKILLS · INSTALLED", tint: LED.green)
                    Text("Skills")
                        .font(LED.display(13, .bold))
                        .foregroundStyle(LED.text)
                }
                Spacer(minLength: 6)
                LEDChevrons(pointingRight: true, count: 3, tint: LED.green, size: 6)
                countReadout(code: "CLAUDE", value: store.claudeCount)
                countReadout(code: "CODEX", value: store.codexCount)
                Button {
                    store.refresh()
                } label: {
                    if store.scanning { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold)) }
                }
                .buttonStyle(.plain).foregroundStyle(LED.dim)
                .disabled(store.scanning)
            }
        }
    }

    /// 单个数码管读数 + 下方代号标注
    private func countReadout(code: String, value: Int) -> some View {
        VStack(spacing: 3) {
            SevenSegmentText(text: "\(value)", height: 12, color: LED.green)
            LEDCaption(text: code, tint: LED.faint, size: 7)
        }
    }

    // MARK: 搜索 + 工具筛选

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LED.faint)
                LEDTextField(placeholder: "搜索 skill 名字或描述…", text: $search)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(LED.chrome))

            // 只有选中态有胶囊,未选中裸在背景上(与弹窗页签、监控台筛选同一套语言)。
            // 未选中照样白字——灰字会读成禁用态。
            HStack(spacing: 10) {
                ForEach(ToolFilter.allCases) { f in
                    let selected = toolFilter == f
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { toolFilter = f }
                    } label: {
                        Text(f.rawValue)
                            .font(LED.display(10.5, selected ? .bold : .medium))
                            .foregroundStyle(selected ? LED.bg : LED.text)
                            .padding(.horizontal, selected ? 11 : 2).padding(.vertical, 4)
                            .background {
                                if selected {
                                    Capsule().fill(LED.green)
                                        .shadow(color: LED.green.opacity(0.5), radius: 6)
                                        .matchedGeometryEffect(id: "led.skillfilter", in: filterNS)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 列表

    @ViewBuilder
    private var skillList: some View {
        if store.scanning && store.skills.isEmpty {
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Text("扫描中…").font(LED.mono(9)).foregroundStyle(LED.faint)
                Spacer()
            }
            .frame(height: 60)
        } else if filtered.isEmpty {
            Text(search.isEmpty ? "还没有安装任何 skill" : "没有匹配「\(search)」的 skill")
                .font(LED.mono(10)).foregroundStyle(LED.faint)
                .frame(maxWidth: .infinity, minHeight: 50)
        } else {
            VStack(spacing: 2) {
                ForEach(filtered) { s in skillRow(s) }
            }
        }
    }

    private func skillRow(_ s: SkillInfo) -> some View {
        let isOpen = expanded == s.id
        // 工具身份色:claude=琥珀 / codex=绿(与本页基调同族,靠灯珠辉光区分)
        let dot = s.tool == .claude ? LED.amber : LED.green
        return VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expanded = isOpen ? nil : s.id
                }
            } label: {
                HStack(spacing: 7) {
                    Circle().fill(dot)
                        .frame(width: 6, height: 6)
                        .shadow(color: dot.opacity(0.9), radius: 3)
                    Text(s.name)
                        .font(LED.display(11, .semibold))
                        .foregroundStyle(LED.text).lineLimit(1)
                    Spacer(minLength: 6)
                    scopeChip(s.scope)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(LED.faint)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    if !s.briefDescription.isEmpty {
                        Text(s.briefDescription).font(LED.mono(9)).foregroundStyle(LED.dim)
                            .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    }
                    if !s.triggerHint.isEmpty {
                        Text("触发:\(s.triggerHint)").font(LED.mono(9)).foregroundStyle(LED.faint)
                            .lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Text(ByteFormat.memory(UInt64(max(0, s.sizeBytes))))
                            .font(LED.mono(8)).foregroundStyle(LED.faint)
                        Spacer()
                        Button("Finder") { store.revealInFinder(s) }
                            .font(LED.mono(9)).buttonStyle(.plain).foregroundStyle(LED.green)
                        if s.scope.isGlobal {
                            Button("复制到 \(s.tool == .claude ? "Codex" : "Claude")") {
                                store.copyToOtherTool(s)
                            }
                            .font(LED.mono(9)).buttonStyle(.plain).foregroundStyle(LED.green)
                        }
                        Button("卸载") { toUninstall = s }
                            .font(LED.mono(9)).buttonStyle(.plain).foregroundStyle(LED.red)
                    }
                }
                .padding(.leading, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            if isOpen {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(LED.green.opacity(0.28), lineWidth: 1)
                    }
            }
        }
        .ledRowHover()
    }

    /// 安装范围徽标:全局=绿(本页基调),项目=中性灰(不抢语义色)
    private func scopeChip(_ scope: SkillScope) -> some View {
        let c = scope.isGlobal ? LED.green : LED.dim
        return Text(scope.label)
            .font(LED.mono(8, .bold))
            .foregroundStyle(c)
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().fill(c.opacity(0.14)))
            .overlay(Capsule().strokeBorder(c.opacity(0.30), lineWidth: 0.5))
    }

    // MARK: 安装区

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                LEDCaption(text: "INSTALL NEW", tint: LED.green)
                Text("安装新 Skill")
                    .font(LED.display(11, .semibold))
                    .foregroundStyle(LED.dim)
            }
            HStack(spacing: 6) {
                LEDTextField(placeholder: "owner/repo 或 GitHub 链接", text: $repoInput)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(LED.chrome))
                    .disabled(store.busy)
                installMenu(label: store.busy ? "…" : "安装", primary: true) { tools in
                    store.installFromGitHub(repoInput, to: tools)
                }
                .disabled(store.busy || repoInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                installMenu(label: "本地文件夹…", primary: false) { tools in
                    store.installFromFolder(to: tools)
                }
                .disabled(store.busy)
                Spacer()
                Link("浏览 skills.sh", destination: URL(string: "https://skills.sh")!)
                    .font(LED.mono(8)).foregroundStyle(LED.dim)
            }
        }
    }

    /// 安装目标选择菜单(Claude / Codex / 两者)。
    /// primary = 主 CTA(黄胶囊);Menu 用不了 ButtonStyle,胶囊由 LEDMenuLabel 自绘。
    private func installMenu(label: String, primary: Bool, action: @escaping ([ToolKind]) -> Void) -> some View {
        Menu {
            Button("装到 Claude Code") { action([.claude]) }
            Button("装到 Codex") { action([.codex]) }
            Button("两个都装") { action([.claude, .codex]) }
        } label: {
            LEDMenuLabel(text: label, primary: primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Menu 的 label。Menu 不接受 ButtonStyle,所以这里手工复刻 LEDGhostButtonStyle 的外观。
/// **改幽灵按钮样式时这里要一起改**——复刻件不会自动跟着走。
/// isEnabled 由外层 .disabled() 经 environment 传进来。
private struct LEDMenuLabel: View {
    let text: String
    let primary: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        Text(text)
            .font(LED.display(11, .bold))
            .foregroundStyle(LED.amber)
            .padding(.horizontal, primary ? 16 : 11).padding(.vertical, primary ? 7 : 4.5)
            .background {
                ZStack {
                    Capsule().fill(LED.amber.opacity(hover ? 0.16 : 0.06))
                    Capsule().fill(LinearGradient(colors: [.white.opacity(0.07), .clear],
                                                  startPoint: .top, endPoint: .center))
                    LEDDotMatrix(tint: LED.amber, pitch: 3, alpha: hover ? 0.22 : 0.14)
                    Capsule().strokeBorder(LED.amber.opacity(hover ? 0.95 : (primary ? 0.7 : 0.5)),
                                           lineWidth: primary ? 1.5 : 1)
                }
                .clipShape(Capsule())
            }
            .shadow(color: LED.amber.opacity(hover ? 0.5 : (primary ? 0.25 : 0.10)), radius: hover ? 9 : 5)
            .opacity(isEnabled ? 1 : 0.3)
            .animation(.easeOut(duration: 0.12), value: hover)
            .onHover { hover = isEnabled && $0 }
    }
}

/// 单仓多 skill 的挑选面板(LED 主题;sheet 不继承宿主背景,自己铺近黑底)
private struct LEDMultiSkillPicker: View {
    let pending: SkillManagerStore.PendingInstall
    @ObservedObject var store: SkillManagerStore
    @State private var selected: Set<String> = []
    @State private var target: [ToolKind] = [.claude]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                LEDCaption(text: "SELECT SKILLS", tint: LED.green)
                Text("\(pending.repoLabel) 里有 \(pending.candidates.count) 个 skill")
                    .font(LED.display(13, .bold))
                    .foregroundStyle(LED.text)
            }
            Text("勾选要安装的:").font(LED.mono(9)).foregroundStyle(LED.dim)

            HUDScrollView(accent: LED.amber) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pending.candidates, id: \.path) { c in
                        candidateRow(c)
                    }
                }
            }
            .frame(maxHeight: 180)

            HStack(spacing: 6) {
                Text("装到").font(LED.mono(9)).foregroundStyle(LED.dim)
                ForEach(targetOptions.indices, id: \.self) { i in
                    let opt = targetOptions[i]
                    let on = target == opt.tools
                    Button(opt.label) { target = opt.tools }
                        .buttonStyle(LEDPillButtonStyle(
                            fill: on ? LED.green : LED.chrome,
                            foreground: on ? .black : LED.dim,
                            size: 10, glow: on))
                }
                Spacer(minLength: 0)
            }

            HStack {
                Button("取消") {
                    store.completePendingInstall(pending, selected: [], to: [])
                }
                .buttonStyle(LEDGhostButtonStyle(size: 11))
                Spacer()
                Button("安装 \(selected.count) 个") {
                    let chosen = pending.candidates.filter { selected.contains($0.path) }
                    store.completePendingInstall(pending, selected: chosen, to: target)
                }
                .buttonStyle(LEDGhostButtonStyle(size: 11, prominent: true))
                .disabled(selected.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(LED.bg)
    }

    /// 与 HUD/经典版 segmented picker 等价的三档:Claude / Codex / 两者
    private var targetOptions: [(label: String, tools: [ToolKind])] {
        [("Claude", [.claude]), ("Codex", [.codex]), ("两者", [.claude, .codex])]
    }

    /// 勾选行:灯珠式 checkmark(替代 Toggle,绑定语义不变)
    private func candidateRow(_ c: (name: String, path: String)) -> some View {
        let on = selected.contains(c.path)
        return Button {
            if on { selected.remove(c.path) } else { selected.insert(c.path) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(on ? LED.green : LED.faint)
                    .shadow(color: on ? LED.green.opacity(0.7) : .clear, radius: 3)
                Text(c.name)
                    .font(LED.mono(10))
                    .foregroundStyle(on ? LED.text : LED.dim)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ledRowHover()
    }
}
