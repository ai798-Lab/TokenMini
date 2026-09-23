import SwiftUI

/// Skills 页签(专业模式第三 tab):查看/搜索 Claude Code 与 Codex 的已装 skill,
/// 支持 GitHub(owner/repo)与本地文件夹安装、卸载(进废纸篓)、跨工具复制。
struct HUDSkillsPanelView: View {
    @EnvironmentObject var store: SkillManagerStore
    @ObservedObject private var settings = DisplaySettings.shared
    @State private var search = ""
    @State private var toolFilter: ToolFilter = .all
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
                Text(msg).font(HUD.mono(8)).foregroundStyle(HUD.dim)
                    .lineLimit(2)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, settings.isPrism ? Prism.contentInset : 12)
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
            MultiSkillPicker(pending: pending, store: store)
        }
    }

    // MARK: 统计 + 控件

    private var statsRow: some View {
        HUDSectionHeader(cn: "Skills", code: "SKL.INSTALLED", trailing: AnyView(
            HStack(spacing: 8) {
                Text("Claude \(store.claudeCount) · Codex \(store.codexCount)")
                    .font(HUD.mono(8)).foregroundStyle(HUD.dim)
                Button {
                    store.refresh()
                } label: {
                    if store.scanning { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 9)) }
                }
                .buttonStyle(.plain).foregroundStyle(HUD.dim)
                .disabled(store.scanning)
            }))
    }

    private var controls: some View {
        VStack(spacing: 6) {
            ThemedSearchField(title: "搜索 skill 名字或描述…", text: $search)
            if settings.isPrism {
                ThemedSegmented(items: ToolFilter.allCases.map { ($0, $0.rawValue) }, selection: $toolFilter, fillsWidth: true)
            } else {
            HStack(spacing: 4) {
                ForEach(ToolFilter.allCases) { f in
                    let selected = toolFilter == f
                    Button {
                        toolFilter = f
                    } label: {
                        Text(f.rawValue)
                            .font(HUD.mono(9, selected ? .bold : .medium))
                            .foregroundStyle(selected ? HUD.cyan : HUD.dim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background {
                                ZStack {
                                    CutCorner(cut: 4).fill(selected ? HUD.cyan.opacity(0.10) : Color.white.opacity(0.03))
                                    if selected {
                                        CutCorner(cut: 4).stroke(HUD.cyan.opacity(0.45), lineWidth: 1)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            }
        }
    }

    // MARK: 列表

    @ViewBuilder
    private var skillList: some View {
        if store.scanning && store.skills.isEmpty {
            HStack { Spacer(); ProgressView().controlSize(.small); Text("扫描中…").font(HUD.mono(8)).foregroundStyle(HUD.faint); Spacer() }
                .frame(height: 60)
        } else if filtered.isEmpty {
            Text(search.isEmpty ? "还没有安装任何 skill" : "没有匹配「\(search)」的 skill")
                .font(.caption).foregroundStyle(HUD.faint)
                .frame(maxWidth: .infinity, minHeight: 50)
        } else {
            VStack(spacing: 2) {
                ForEach(filtered) { s in skillRow(s) }
            }
        }
    }

    private func skillRow(_ s: SkillInfo) -> some View {
        let isOpen = expanded == s.id
        return VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expanded = isOpen ? nil : s.id
                }
            } label: {
                HStack(spacing: 7) {
                    Rectangle().fill(s.tool == .claude ? HUD.amber : HUD.mint)
                        .frame(width: 6, height: 6)
                    Text(s.name).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HUD.text).lineLimit(1)
                    Spacer(minLength: 6)
                    HUDChip(text: s.scope.label, color: s.scope.isGlobal ? HUD.ice : HUD.violet)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(HUD.faint)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    if !s.briefDescription.isEmpty {
                        Text(s.briefDescription).font(.system(size: 9)).foregroundStyle(HUD.dim)
                            .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    }
                    if !s.triggerHint.isEmpty {
                        Text("触发:\(s.triggerHint)").font(.system(size: 9)).foregroundStyle(HUD.faint)
                            .lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Text(ByteFormat.memory(UInt64(max(0, s.sizeBytes))))
                            .font(HUD.mono(8)).foregroundStyle(HUD.faint)
                        Spacer()
                        Button("Finder") { store.revealInFinder(s) }
                            .font(HUD.mono(9)).buttonStyle(.plain).foregroundStyle(HUD.cyan)
                        if s.scope.isGlobal {
                            Button("复制到 \(s.tool == .claude ? "Codex" : "Claude")") {
                                store.copyToOtherTool(s)
                            }
                            .font(HUD.mono(9)).buttonStyle(.plain).foregroundStyle(HUD.cyan)
                        }
                        Button("卸载") { toUninstall = s }
                            .font(HUD.mono(9)).buttonStyle(.plain).foregroundStyle(HUD.red)
                    }
                }
                .padding(.leading, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            if isOpen && settings.isPrism {
                RoundedRectangle(cornerRadius: Prism.controlRadius).fill(Prism.panelHi)
                    .overlay(RoundedRectangle(cornerRadius: Prism.controlRadius).strokeBorder(Prism.line, lineWidth: 1))
            } else if isOpen {
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.04))
                    CornerBrackets(length: 5).stroke(HUD.cyan.opacity(0.4), lineWidth: 1)
                }
            }
        }
        .hudRowHover()
    }

    // MARK: 安装区

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HUDSectionHeader(cn: "安装新 Skill", code: "SKL.INSTALL", accent: HUD.green)
            HStack(spacing: 6) {
                ThemedSearchField(title: "owner/repo 或 GitHub 链接", text: $repoInput)
                    .disabled(store.busy)
                installMenu(label: store.busy ? "…" : "安装") { tools in
                    store.installFromGitHub(repoInput, to: tools)
                }
                .disabled(store.busy || repoInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                installMenu(label: "本地文件夹…") { tools in
                    store.installFromFolder(to: tools)
                }
                .disabled(store.busy)
                Spacer()
                Link("浏览 skills.sh", destination: URL(string: "https://skills.sh")!)
                    .font(HUD.mono(8)).foregroundStyle(HUD.dim)
            }
        }
    }

    /// 安装目标选择菜单(Claude / Codex / 两者)
    private func installMenu(label: String, action: @escaping ([ToolKind]) -> Void) -> some View {
        ThemedActionMenu(title: label, actions: [
            ("装到 Claude Code", { action([.claude]) }),
            ("装到 Codex", { action([.codex]) }),
            ("两个都装", { action([.claude, .codex]) })
        ])

    }
}

/// 单仓多 skill 的挑选面板
private struct MultiSkillPicker: View {
    let pending: SkillManagerStore.PendingInstall
    @ObservedObject var store: SkillManagerStore
    @State private var selected: Set<String> = []
    @State private var target: [ToolKind] = [.claude]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(pending.repoLabel) 里有 \(pending.candidates.count) 个 skill")
                .font(.headline)
            Text("勾选要安装的:").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pending.candidates, id: \.path) { c in
                        Toggle(c.name, isOn: Binding(
                            get: { selected.contains(c.path) },
                            set: { on in if on { selected.insert(c.path) } else { selected.remove(c.path) } }))
                            .font(.caption).toggleStyle(ThemedCheckToggleStyle())
                    }
                }
            }
            .frame(maxHeight: 180)
            ThemedSegmented(items: [(0, "Claude"), (1, "Codex"), (2, "两者")], selection: Binding(
                get: { target.count == 2 ? 2 : (target.first == .claude ? 0 : 1) },
                set: { v in target = v == 2 ? [.claude, .codex] : (v == 0 ? [.claude] : [.codex]) }), fillsWidth: true)
            HStack {
                Button("取消") {
                    store.completePendingInstall(pending, selected: [], to: [])
                }
                Spacer()
                Button("安装 \(selected.count) 个") {
                    let chosen = pending.candidates.filter { selected.contains($0.path) }
                    store.completePendingInstall(pending, selected: chosen, to: target)
                }
                .buttonStyle(HUDButtonStyle(filled: true))
                .disabled(selected.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(HUD.bg).foregroundStyle(HUD.text).tint(HUD.cyan)
    }
}
