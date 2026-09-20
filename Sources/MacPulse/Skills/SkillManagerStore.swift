import Foundation
import Combine
import AppKit

/// Skill 管理中心:列出 / 安装 / 卸载 / 跨工具复制。
/// 安装约定对齐开源生态(skills.sh 的 npx skills add、sk install):
/// 支持 owner/repo、owner/repo/子路径、完整 GitHub URL,git clone 后自动发现仓库里所有含
/// SKILL.md 的目录(单仓多 skill),再拷入目标 agent 的 skills 目录。
/// 卸载比生态更安全:移入废纸篓(可恢复),不做 rm。
@MainActor
final class SkillManagerStore: ObservableObject {
    @Published private(set) var skills: [SkillInfo] = []
    @Published private(set) var scanning = false
    @Published var busy = false                 // 安装/卸载进行中
    @Published var lastMessage: String?         // 操作结果反馈(成功/失败一句话)
    @Published var pendingInstall: PendingInstall?  // 单仓多 skill 时待用户挑选

    struct PendingInstall: Identifiable {
        let id = UUID()
        let repoLabel: String
        let tempRoot: String                    // 临时 clone 目录(挑选完/取消后清理)
        let candidates: [(name: String, path: String)]
    }

    private let scanner = SkillScanner()
    private let queue = DispatchQueue(label: "macpulse.skills", qos: .userInitiated)

    /// 供预览/离屏渲染注入现成数据(不触发扫描)
    func injectForPreview(_ s: [SkillInfo]) { skills = s }

    var claudeCount: Int { skills.filter { $0.tool == .claude }.count }
    var codexCount: Int { skills.filter { $0.tool == .codex }.count }

    // MARK: - 刷新

    func refresh() {
        guard !scanning else { return }
        scanning = true
        let scanner = self.scanner
        queue.async { [weak self] in
            scanner.invalidateProjectCache()
            let list = scanner.scanAll()
            Task { @MainActor in
                guard let self else { return }
                self.skills = list
                self.scanning = false
            }
        }
    }

    // MARK: - 卸载(移入废纸篓,可恢复)

    func uninstall(_ skill: SkillInfo) {
        guard !busy, pendingInstall == nil else { return }
        guard Self.isSafeInstalledSkillDirectory(skill.directory) else {
            lastMessage = "卸载已取消:skill 路径未通过安全校验"
            return
        }
        busy = true
        queue.async { [weak self] in
            var result: String
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: skill.directory), resultingItemURL: nil)
                result = "已把「\(skill.name)」移到废纸篓(可恢复)"
            } catch {
                result = "卸载失败:\(error.localizedDescription)"
            }
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.lastMessage = result
                self.refresh()
            }
        }
    }

    // MARK: - 跨工具复制(claude ↔ codex 全局)

    func copyToOtherTool(_ skill: SkillInfo) {
        guard !busy, pendingInstall == nil else { return }
        let target = skill.tool == .claude ? SkillScanner.codexGlobalDir : SkillScanner.claudeGlobalDir
        let targetTool: ToolKind = skill.tool == .claude ? .codex : .claude
        busy = true
        queue.async { [weak self] in
            let result = Self.copySkillDir(from: skill.directory, intoRoot: target)
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.lastMessage = result == nil
                    ? "已复制「\(skill.name)」到 \(targetTool.label)"
                    : "复制失败:\(result!)"
                self.refresh()
            }
        }
    }

    // MARK: - 本地文件夹安装

    func installFromFolder(to tools: [ToolKind]) {
        guard !busy, pendingInstall == nil else { return }
        guard !tools.isEmpty else { lastMessage = "请至少选择一个安装目标"; return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择一个包含 SKILL.md 的 skill 文件夹"
        panel.prompt = "安装"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.fileExists(atPath: url.path + "/SKILL.md") else {
            lastMessage = "该文件夹里没有 SKILL.md,不是有效的 skill"
            return
        }
        install(dirs: [(url.lastPathComponent, url.path)], to: tools, cleanup: nil)
    }

    // MARK: - GitHub 安装(owner/repo | owner/repo/path | 完整 URL)

    func installFromGitHub(_ input: String, to tools: [ToolKind]) {
        guard !busy, pendingInstall == nil else { return }
        guard !tools.isEmpty else { lastMessage = "请至少选择一个安装目标"; return }
        let spec = Self.parseRepoSpec(input)
        guard let spec else { lastMessage = "无法识别:请输入 owner/repo 或 GitHub 链接"; return }
        busy = true
        lastMessage = "正在从 \(spec.owner)/\(spec.repo) 拉取…"
        let toolsCopy = tools
        queue.async { [weak self] in
            let tmp = NSTemporaryDirectory() + "macpulse-skill-\(UUID().uuidString)"
            let cloneURL = "https://github.com/\(spec.owner)/\(spec.repo).git"
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = ["-c", "http.lowSpeedLimit=1000", "-c", "http.lowSpeedTime=30",
                             "clone", "--depth", "1"]
            if let branch = spec.branch { git.arguments! += ["--branch", branch, "--single-branch"] }
            git.arguments! += ["--", cloneURL, tmp]
            git.environment = ProcessInfo.processInfo.environment.merging(["GIT_TERMINAL_PROMPT": "0"]) { _, new in new }
            git.standardOutput = FileHandle.nullDevice
            git.standardError = FileHandle.nullDevice
            do {
                try git.run()
                let timeout = DispatchWorkItem { if git.isRunning { git.terminate() } }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60, execute: timeout)
                git.waitUntilExit()
                timeout.cancel()
            } catch {
                Task { @MainActor in self?.busy = false; self?.lastMessage = "git 启动失败" }
                return
            }
            guard git.terminationStatus == 0 else {
                Task { @MainActor in
                    self?.busy = false
                    self?.lastMessage = "拉取失败:仓库不存在或网络不通"
                }
                try? FileManager.default.removeItem(atPath: tmp)
                return
            }
            // 在仓库(或指定子路径)里找所有含 SKILL.md 的目录
            let searchRoot = spec.subpath.isEmpty ? tmp : tmp + "/" + spec.subpath
            let candidates = Self.findSkillDirs(under: searchRoot, tmpRoot: tmp)
            Task { @MainActor in
                guard let self else { try? FileManager.default.removeItem(atPath: tmp); return }
                self.busy = false
                switch candidates.count {
                case 0:
                    self.lastMessage = "仓库里没找到 SKILL.md"
                    try? FileManager.default.removeItem(atPath: tmp)
                case 1:
                    self.install(dirs: candidates, to: toolsCopy, cleanup: tmp)
                default:
                    // 单仓多 skill:交给 UI 弹选择
                    self.pendingInstall = PendingInstall(
                        repoLabel: "\(spec.owner)/\(spec.repo)",
                        tempRoot: tmp, candidates: candidates)
                }
            }
        }
    }

    /// 用户从多 skill 仓库里挑选后调用;selected 为空 = 取消
    func completePendingInstall(_ pending: PendingInstall, selected: [(name: String, path: String)], to tools: [ToolKind]) {
        pendingInstall = nil
        if selected.isEmpty || tools.isEmpty {
            try? FileManager.default.removeItem(atPath: pending.tempRoot)
            if !selected.isEmpty { lastMessage = "请至少选择一个安装目标" }
            return
        }
        install(dirs: selected, to: tools, cleanup: pending.tempRoot)
    }

    // MARK: - 内部:批量安装 + 工具集

    private func install(dirs: [(name: String, path: String)], to tools: [ToolKind], cleanup: String?) {
        guard !tools.isEmpty else {
            if let cleanup { try? FileManager.default.removeItem(atPath: cleanup) }
            lastMessage = "请至少选择一个安装目标"
            return
        }
        busy = true
        queue.async { [weak self] in
            var installed = 0
            var errors: [String] = []
            for tool in tools {
                let root = tool == .claude ? SkillScanner.claudeGlobalDir : SkillScanner.codexGlobalDir
                for (_, path) in dirs {
                    if let err = Self.copySkillDir(from: path, intoRoot: root) { errors.append(err) }
                    else { installed += 1 }
                }
            }
            if let cleanup { try? FileManager.default.removeItem(atPath: cleanup) }
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.lastMessage = errors.isEmpty
                    ? "已安装 \(installed) 个 skill"
                    : "完成 \(installed) 个,失败:\(errors.first ?? "未知错误")"
                self.refresh()
            }
        }
    }

    /// 拷贝 skill 目录到目标根;同名已存在则拒绝(避免覆盖用户本地修改)。返回错误描述或 nil。
    nonisolated private static func copySkillDir(from src: String, intoRoot root: String) -> String? {
        let fm = FileManager.default
        guard isSafeSkillSource(src) else { return "来源目录包含不安全的符号链接或缺少 SKILL.md" }
        guard isSafeSkillRoot(root) else { return "目标 skills 目录是符号链接或路径异常" }
        let name = (src as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { return "skill 目录名无效" }
        let dst = root + "/" + name
        do {
            try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dst) { return "「\(name)」已存在(先卸载旧的)" }
            try fm.copyItem(atPath: src, toPath: dst)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 找 root 下所有含 SKILL.md 的目录(根自身优先;限深防巨仓)
    nonisolated private static func findSkillDirs(under root: String, tmpRoot: String) -> [(name: String, path: String)] {
        let fm = FileManager.default
        let tmpURL = URL(fileURLWithPath: tmpRoot, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let rootURL = URL(fileURLWithPath: root, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        guard isInside(rootURL, root: tmpURL) else { return [] }
        if fm.fileExists(atPath: rootURL.appendingPathComponent("SKILL.md").path) {
            return [(rootURL.lastPathComponent, rootURL.path)]
        }
        var found: [(String, String)] = []
        var seen = Set<String>()
        guard let en = fm.enumerator(at: rootURL,
                                     includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in en {
            if en.level > 4 { en.skipDescendants(); continue }
            if url.lastPathComponent == "SKILL.md" {
                let dir = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
                guard isInside(dir, root: tmpURL), seen.insert(dir.path).inserted else {
                    en.skipDescendants(); continue
                }
                found.append((dir.lastPathComponent, dir.path))
                en.skipDescendants()
            }
        }
        return found.sorted { $0.0 < $1.0 }
    }

    /// 解析 "owner/repo"、"owner/repo/sub/path"、完整 GitHub URL
    nonisolated static func parseRepoSpec(_ raw: String) -> (owner: String, repo: String, subpath: String, branch: String?)? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        for prefix in ["https://github.com/", "http://github.com/", "github.com/", "git@github.com:"] {
            if s.lowercased().hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        var branch: String?
        // 保留 /tree/<branch>，否则会静默安装默认分支的内容。
        if let r = s.range(of: "/tree/") {
            let after = s[r.upperBound...]
            let parts = after.split(separator: "/", maxSplits: 1)
            guard let rawBranch = parts.first, let decoded = String(rawBranch).removingPercentEncoding,
                  !decoded.isEmpty, !decoded.hasPrefix("-"), !decoded.contains(".."),
                  !decoded.contains(" "), !decoded.contains("\n") else { return nil }
            branch = decoded
            s = String(s[..<r.lowerBound]) + (parts.count > 1 ? "/" + parts[1] : "")
        }
        let comps = s.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard comps.count >= 2 else { return nil }
        let validNameChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        func validName(_ value: String) -> Bool {
            !value.isEmpty && value.unicodeScalars.allSatisfy { validNameChars.contains($0) }
        }
        guard comps[0] != ".", comps[0] != "..", comps[1] != ".", comps[1] != "..",
              validName(comps[0]), validName(comps[1]) else { return nil }
        let pathParts = comps.dropFirst(2)
        guard pathParts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        let sub = comps.count > 2 ? comps[2...].joined(separator: "/") : ""
        return (comps[0], comps[1], sub, branch)
    }

    nonisolated private static func isInside(_ candidate: URL, root: URL) -> Bool {
        let p = candidate.path, r = root.path
        return p == r || p.hasPrefix(r + "/")
    }

    /// 已安装项只能是 `.claude/skills` 或 `.codex/skills` 的直接子项,且 skills 根不能经符号链接跳转。
    nonisolated private static func isSafeInstalledSkillDirectory(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let parent = url.deletingLastPathComponent()
        guard url.lastPathComponent != ".", url.lastPathComponent != "..",
              parent.path.hasSuffix("/.claude/skills") || parent.path.hasSuffix("/.codex/skills"),
              parent.resolvingSymlinksInPath().standardizedFileURL.path == parent.path else { return false }
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    /// 安装目标不存在时可以创建;一旦存在,真实路径必须仍是原路径,不能把全局 skills 根链接到别处。
    nonisolated private static func isSafeSkillRoot(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard url.path.hasSuffix("/.claude/skills") || url.path.hasSuffix("/.codex/skills") else { return false }
        return url.resolvingSymlinksInPath().standardizedFileURL.path == url.path
    }

    /// 不安装符号链接 skill 或含链接的目录,避免 clone 临时目录删除后留下断链,
    /// 也避免恶意仓库把链接指向 repo/用户目录之外。
    nonisolated private static func isSafeSkillSource(_ path: String) -> Bool {
        let fm = FileManager.default
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) != S_IFLNK,
              fm.fileExists(atPath: path + "/SKILL.md") else { return false }
        guard let en = fm.enumerator(at: URL(fileURLWithPath: path),
                                     includingPropertiesForKeys: [.isSymbolicLinkKey],
                                     options: [.skipsHiddenFiles]) else { return false }
        for case let url as URL in en {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                return false
            }
        }
        return true
    }

    // MARK: - 辅助

    func revealInFinder(_ skill: SkillInfo) {
        NSWorkspace.shared.selectFile(skill.directory + "/SKILL.md",
                                      inFileViewerRootedAtPath: skill.directory)
    }
}
