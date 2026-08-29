import Foundation
import LocalAuthentication
import Security

enum ClaudeKeychainAccessMode {
    case background
    case userInitiated
}

/// Claude 额度:读 Keychain 的 OAuth token,调未公开的用量端点拿到权威的 5h/周额度。
/// 端点:GET https://api.anthropic.com/api/oauth/usage —— 返回 five_hour/seven_day 的
/// utilization(0~100)+ resets_at(ISO)。低频调用避免 429。
/// token 在 Keychain(Claude Code-credentials),仅在用户主动开启后读取;拿不到就返回 nil。
final class ClaudeQuotaReader {
    // 用 Claude Code 的 UA(错的 UA 会被严格限流);版本号可旧,不影响用量端点。
    private static let userAgent = "claude-code/2.1.201"
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private static func dbg(_ s: String) {
        guard ProcessInfo.processInfo.environment["MACPULSE_QUOTA_DBG"] != nil else { return }
        let line = "[claude] \(s)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/mp_claude.log") { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.data(using: .utf8)!.write(to: URL(fileURLWithPath: "/tmp/mp_claude.log")) }
    }

    func fetch(accessMode: ClaudeKeychainAccessMode = .background) async -> ToolQuota? {
        guard let cred = keychainCredentials(accessMode: accessMode) else { Self.dbg("keychain 读取失败(被拒/不存在)"); return nil }
        guard let oauth = cred["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { Self.dbg("凭证结构异常"); return nil }
        let plan = oauth["subscriptionType"] as? String
        Self.dbg("keychain OK, plan=\(plan ?? "?")")

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { Self.dbg("网络请求抛错"); return nil }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        Self.dbg("HTTP \(code)")
        guard code == 200, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let q = Self.parse(obj, plan: plan)
        Self.dbg("parse → \(q == nil ? "nil" : "\(q!.windows.count) 窗口")")
        return q
    }

    /// 直接通过 Security.framework 读 Keychain，避免启动 `security` 子进程。
    /// 只请求单条原始 Data；OAuth token 仅存在于当前调用栈，不落盘、不写日志。
    private func keychainCredentials(accessMode: ClaudeKeychainAccessMode) -> [String: Any]? {
        let query = Self.keychainQuery(accessMode: accessMode)
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    /// 启动与定时刷新不得在用户没有操作 MacPulse 时弹出系统认证框。
    /// 只有用户在设置中明确开启实验功能时，才使用系统默认的可交互策略。
    static func keychainQuery(accessMode: ClaudeKeychainAccessMode) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials",
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]
        if case .background = accessMode {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = context
            // Claude Code 的条目可能位于传统“登录”钥匙串；Skip 是
            // SecItemCopyMatching 专用的静默策略，作为第二层保证避免 ACL 授权框。
            query[kSecUseAuthenticationUI] = kSecUseAuthenticationUISkip
        }
        return query
    }

    static func parse(_ d: [String: Any], plan: String?) -> ToolQuota? {
        let now = Date()
        var windows: [QuotaWindow] = []
        func win(_ key: String, _ kind: QuotaKind) -> QuotaWindow? {
            guard let w = d[key] as? [String: Any],
                  let util = (w["utilization"] as? NSNumber)?.doubleValue,
                  let ra = w["resets_at"] as? String,
                  let reset = parseISO(ra) else { return nil }
            guard util.isFinite else { return nil }
            return QuotaWindow(tool: .claude, kind: kind,
                               usedPercent: min(100, max(0, util)), resetsAt: reset, asOf: now)
        }
        if let f = win("five_hour", .fiveHour) { windows.append(f) }
        if let s = win("seven_day", .weekly) { windows.append(s) }
        guard !windows.isEmpty else { return nil }
        return ToolQuota(tool: .claude, plan: plan, windows: windows, authoritative: true, asOf: now)
    }

    static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        let g = ISO8601DateFormatter(); g.formatOptions = [.withInternetDateTime]
        return g.date(from: s)
    }
}
