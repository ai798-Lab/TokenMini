import Foundation

/// Skill 的安装范围
enum SkillScope: Equatable, Sendable {
    case global                 // ~/.claude/skills 或 ~/.codex/skills
    case project(String)        // <项目>/.claude/skills,关联值 = 项目名(basename)

    var label: String {
        switch self {
        case .global: return "全局"
        case .project(let name): return "项目 · \(name)"
        }
    }
    var isGlobal: Bool { if case .global = self { return true }; return false }
}

/// 一个已安装的 skill(一条 = 一个含 SKILL.md 的目录)
struct SkillInfo: Identifiable, Sendable {
    let tool: ToolKind          // claude / codex(复用现有枚举)
    let scope: SkillScope
    let name: String            // frontmatter name,缺省用目录名
    let description: String     // frontmatter description(压成单段)
    let directory: String       // skill 目录绝对路径
    let sizeBytes: Int64        // 目录体积(浅算,显示用)

    var id: String { directory }

    /// 触发短语行(description 里"触发短语:"之后的部分),没有则空
    var triggerHint: String {
        for marker in ["触发短语：", "触发短语:"] {
            if let r = description.range(of: marker) {
                return String(description[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    /// 去掉触发短语后的简介首句
    var briefDescription: String {
        var d = description
        for marker in ["触发短语：", "触发短语:"] {
            if let r = d.range(of: marker) {
                d = String(d[..<r.lowerBound])
                break
            }
        }
        return d.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
