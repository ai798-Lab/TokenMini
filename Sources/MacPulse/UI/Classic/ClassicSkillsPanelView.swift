import SwiftUI

/// 经典主题·Skills 页签:查看/搜索 Claude Code 与 Codex 的已装 skill,
/// 支持 GitHub(owner/repo)与本地文件夹安装、卸载(进废纸篓)、跨工具复制。
struct ClassicSkillsPanelView: View {
    @EnvironmentObject var store: SkillManagerStore
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
            Divider()
            installSection
            if let msg = store.lastMessage {
                Text(msg).font(.caption2).foregroundStyle(.secondary)
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
            ClassicMultiSkillPicker(pending: pending, store: store)
        }
    }

    // MARK: 统计 + 控件

    private var statsRow: some View {
        HStack {
            Label("Skills", systemImage: "puzzlepiece.extension")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Text("Claude \(store.claudeCount) · Codex \(store.codexCount)")
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            Button {
                store.refresh()
            } label: {
                if store.scanning { ProgressView().controlSize(.mini) }
                else { Image(systemName: "arrow.clockwise").font(.caption2) }
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .disabled(store.scanning)
        }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            TextField("搜索 skill 名字或描述…", text: $search)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            Picker("", selection: $toolFilter) {
                ForEach(ToolFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
    }

    // MARK: 列表

    @ViewBuilder
    private var skillList: some View {
        if store.scanning && store.skills.isEmpty {
            HStack { Spacer(); ProgressView().controlSize(.small); Text("扫描中…").font(.caption2).foregroundStyle(.tertiary); Spacer() }
                .frame(height: 60)
        } else if filtered.isEmpty {
            Text(search.isEmpty ? "还没有安装任何 skill" : "没有匹配「\(search)」的 skill")
                .font(.caption).foregroundStyle(.tertiary)
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
                    Circle().fill(s.tool == .claude ? Color.orange : .teal)
                        .frame(width: 7, height: 7)
                    Text(s.name).font(.caption.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(s.scope.label)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background((s.scope.isGlobal ? Color.blue : .purple).opacity(0.14),
                                    in: Capsule())
                        .foregroundStyle(s.scope.isGlobal ? Color.blue : .purple)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    if !s.briefDescription.isEmpty {
                        Text(s.briefDescription).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    }
                    if !s.triggerHint.isEmpty {
                        Text("触发:\(s.triggerHint)").font(.system(size: 10)).foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Text(ByteFormat.memory(UInt64(max(0, s.sizeBytes))))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                        Spacer()
                        Button("Finder") { store.revealInFinder(s) }
                            .font(.caption2).buttonStyle(.plain).foregroundStyle(.blue)
                        if s.scope.isGlobal {
                            Button("复制到 \(s.tool == .claude ? "Codex" : "Claude")") {
                                store.copyToOtherTool(s)
                            }
                            .font(.caption2).buttonStyle(.plain).foregroundStyle(.blue)
                        }
                        Button("卸载") { toUninstall = s }
                            .font(.caption2).buttonStyle(.plain).foregroundStyle(.red)
                    }
                }
                .padding(.leading, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isOpen ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 7))
    }

    // MARK: 安装区

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("安装新 Skill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField("owner/repo 或 GitHub 链接", text: $repoInput)
                    .textFieldStyle(.roundedBorder).controlSize(.small)
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
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// 安装目标选择菜单(Claude / Codex / 两者)
    private func installMenu(label: String, action: @escaping ([ToolKind]) -> Void) -> some View {
        Menu {
            Button("装到 Claude Code") { action([.claude]) }
            Button("装到 Codex") { action([.codex]) }
            Button("两个都装") { action([.claude, .codex]) }
        } label: {
            Text(label).font(.caption)
        }
        .menuStyle(.button).buttonStyle(.bordered).controlSize(.small)
        .fixedSize()
    }
}

/// 单仓多 skill 的挑选面板(经典主题;sheet 里系统样式即可)
private struct ClassicMultiSkillPicker: View {
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
                            .font(.caption)
                    }
                }
            }
            .frame(maxHeight: 180)
            Picker("装到", selection: Binding(
                get: { target.count == 2 ? 2 : (target.first == .claude ? 0 : 1) },
                set: { v in target = v == 2 ? [.claude, .codex] : (v == 0 ? [.claude] : [.codex]) })) {
                Text("Claude").tag(0); Text("Codex").tag(1); Text("两者").tag(2)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("取消") {
                    store.completePendingInstall(pending, selected: [], to: [])
                }
                Spacer()
                Button("安装 \(selected.count) 个") {
                    let chosen = pending.candidates.filter { selected.contains($0.path) }
                    store.completePendingInstall(pending, selected: chosen, to: target)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
