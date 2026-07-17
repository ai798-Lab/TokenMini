import Foundation

/// Skill 扫描器:发现 Claude Code / Codex 已安装的 skills(全局 + Claude 项目级)。
/// 目录约定(与开源生态一致:skills.sh / sk / yibie/skills-manager):
///   Claude 全局   ~/.claude/skills/<name>/SKILL.md
///   Codex 全局    ~/.codex/skills/<name>/SKILL.md
///   Claude 项目级 <项目>/.claude/skills/<name>/SKILL.md
/// 项目路径从 ~/.claude/projects 的编码目录名回溯还原(fileExists 校验,best-effort)。
/// 线程契约:只在 SkillManagerStore 的串行队列上调用。
final class SkillScanner: @unchecked Sendable {

    static var claudeGlobalDir: String { NSHomeDirectory() + "/.claude/skills" }
    static var codexGlobalDir: String { NSHomeDirectory() + "/.codex/skills" }

    func scanAll() -> [SkillInfo] {
        var out: [SkillInfo] = []
        out += scan(dir: Self.claudeGlobalDir, tool: .claude, scope: .global)
        out += scan(dir: Self.codexGlobalDir, tool: .codex, scope: .global)
        for project in discoverClaudeProjects() {
            let name = (project as NSString).lastPathComponent
            out += scan(dir: project + "/.claude/skills", tool: .claude, scope: .project(name))
        }
        // 名字排序,全局在前
        return out.sorted {
            if $0.scope.isGlobal != $1.scope.isGlobal { return $0.scope.isGlobal }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - 单目录扫描

    private func scan(dir: String, tool: ToolKind, scope: SkillScope) -> [SkillInfo] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [SkillInfo] = []
        for child in children where !child.hasPrefix(".") {
            let skillDir = dir + "/" + child
            let manifest = skillDir + "/SKILL.md"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: skillDir, isDirectory: &isDir), isDir.boolValue,
                  fm.fileExists(atPath: manifest) else { continue }
            let fm2 = Self.parseFrontmatter(at: manifest)
            out.append(SkillInfo(
                tool: tool, scope: scope,
                name: fm2.name ?? child,
                description: fm2.description ?? "",
                directory: skillDir,
                sizeBytes: Self.shallowSize(of: skillDir)))
        }
        return out
    }

    // MARK: - frontmatter 宽松解析(name / description,description 支持 `|` 块标量)

    static func parseFrontmatter(at path: String) -> (name: String?, description: String?) {
        guard let handle = FileHandle(forReadingAtPath: path),
              let data = try? handle.read(upToCount: 8192),
              let text = String(data: data, encoding: .utf8) else { return (nil, nil) }
        try? handle.close()

        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, nil) }

        var name: String?
        var desc: String?
        var i = 1
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }                      // frontmatter 结束
            if trimmed.hasPrefix("name:") {
                name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } else if trimmed.hasPrefix("description:") {
                let rest = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
                if rest == "|" || rest == ">" || rest == "|-" || rest == ">-" {
                    // 块标量:收集后续缩进行直到非缩进
                    var parts: [String] = []
                    var j = i + 1
                    while j < lines.count {
                        let l = lines[j]
                        if l.trimmingCharacters(in: .whitespaces) == "---" { break }
                        if l.hasPrefix("  ") || l.hasPrefix("\t") || l.trimmingCharacters(in: .whitespaces).isEmpty {
                            parts.append(l.trimmingCharacters(in: .whitespaces))
                            j += 1
                        } else { break }
                    }
                    desc = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    i = j - 1
                } else {
                    desc = rest.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
            i += 1
        }
        return (name?.isEmpty == false ? name : nil, desc?.isEmpty == false ? desc : nil)
    }

    // MARK: - 目录体积(有限枚举,防超大目录拖慢)

    static func shallowSize(of dir: String) -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: URL(fileURLWithPath: dir),
                                     includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        var count = 0
        for case let url as URL in en {
            count += 1
            if count > 2000 { break }                          // 上限,显示用不必精确
            guard let rv = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  rv.isRegularFile == true else { continue }
            total += Int64(rv.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Claude 项目发现(编码目录名 → 真路径,回溯 + 存在性校验)

    private var cachedProjects: [String]?

    func discoverClaudeProjects() -> [String] {
        if let cached = cachedProjects { return cached }
        let fm = FileManager.default
        let projectsDir = NSHomeDirectory() + "/.claude/projects"
        guard let names = try? fm.contentsOfDirectory(atPath: projectsDir) else {
            cachedProjects = []; return []
        }
        let home = NSHomeDirectory()
        var found = Set<String>()
        for name in names {
            // 编码目录名对含中文/空格的路径不可逆(字符全变 "-"),优先从该项目的
            // 会话 JSONL 里读真实 cwd(无损);读不到再回退字面解码。
            let path = Self.cwdFromSessions(projectsDir + "/" + name)
                ?? Self.decodeProjectPath(name)
            guard let path,
                  path != home,                    // home 的 .claude/skills 是全局目录,不能当项目重复算
                  fm.fileExists(atPath: path + "/.claude/skills") else { continue }
            found.insert(path)
        }
        let result = found.sorted()
        cachedProjects = result
        return result
    }

    func invalidateProjectCache() { cachedProjects = nil }

    /// 从项目目录里最新的会话 JSONL 头部读真实 cwd("cwd":"/...")。
    /// 只读最新一个文件的前 64KB,代价可忽略;读不到返回 nil。
    static func cwdFromSessions(_ projectDir: String) -> String? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: projectDir) else { return nil }
        let jsonls = files.filter { $0.hasSuffix(".jsonl") }
        guard !jsonls.isEmpty else { return nil }
        // 按 mtime 新→旧,最多试 3 个文件(最新那个开头可能是超长粘贴行,64KB 里没 cwd)
        let dated: [(String, Date)] = jsonls.map { f in
            let p = projectDir + "/" + f
            let m = (try? fm.attributesOfItem(atPath: p)[.modificationDate] as? Date) ?? .distantPast
            return (p, m)
        }.sorted { $0.1 > $1.1 }
        for (path, _) in dated.prefix(3) {
            guard let h = FileHandle(forReadingAtPath: path),
                  let data = try? h.read(upToCount: 65536) else { continue }
            try? h.close()
            // 超长行可能截断在多字节字符中间,损失容忍地解码
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data.dropLast(3), encoding: .utf8) else { continue }
            guard let r = text.range(of: #""cwd":"([^"]+)""#, options: .regularExpression) else { continue }
            let match = String(text[r])                        // "cwd":"/Users/name/..."
            let cwd = match.dropFirst(#""cwd":""#.count).dropLast(1)
            if !cwd.isEmpty { return String(cwd) }
        }
        return nil
    }

    /// "-Users-name-Documents-Foo-Bar" → "/Users/name/Documents/Foo-Bar"(如果存在)。
    /// 编码把 "/" 与部分字符都变成 "-",不可逆;用回溯:每个 "-" 优先当路径分隔,
    /// 若该前缀目录不存在则并入上一段当字面连字符。段数有限,回溯代价可忽略。
    static func decodeProjectPath(_ encoded: String) -> String? {
        let segs = encoded.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard segs.count > 1, segs[0].isEmpty else { return nil }   // 必须以 "-"(根)开头
        let fm = FileManager.default

        func backtrack(_ idx: Int, _ current: String) -> String? {
            if idx == segs.count {
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: current, isDirectory: &isDir) && isDir.boolValue ? current : nil
            }
            let seg = segs[idx]
            // 真实路径的每个前缀目录必然存在,不存在的分支直接剪掉。
            // 空段(连续 "-",多来自 CJK 等被编码丢失的字符)只能并入上一段,不能当新路径段。
            if !seg.isEmpty {
                let asNew = current + "/" + seg
                if fm.fileExists(atPath: asNew), let r = backtrack(idx + 1, asNew) { return r }
            }
            if !current.isEmpty {
                let merged = current + "-" + seg
                if fm.fileExists(atPath: merged), let r = backtrack(idx + 1, merged) { return r }
            }
            return nil
        }
        return backtrack(1, "")
    }
}
