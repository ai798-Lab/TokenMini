import Foundation

/// 从 ~/.codex/sessions 的 rollout 文件里读取最近一条非空 rate_limits。
/// 数据只到"上次使用 Codex 时"——快照可能陈旧,已重置窗口由 QuotaWindow.hasReset 处理。
/// 线程:在后台队列调用。
final class CodexQuotaReader: @unchecked Sendable {

    func read() -> ToolQuota? {
        let base = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/sessions")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base, isDirectory: &isDir), isDir.boolValue else { return nil }

        // rollout 文件按修改时间倒序,新的先看;找到含非空 rate_limits 的最新一条即停
        let files = rolloutFiles(base: base).sorted { $0.mtime > $1.mtime }
        for f in files.prefix(12) {   // 最近 12 个会话足够,避免全库扫
            if let q = Self.latestRateLimits(in: f.url) { return q }
        }
        return nil
    }

    private struct FileEntry { let url: URL; let mtime: Date }

    private func rolloutFiles(base: String) -> [FileEntry] {
        let baseURL = URL(fileURLWithPath: base, isDirectory: true)
        guard let en = FileManager.default.enumerator(
            at: baseURL, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var out: [FileEntry] = []
        for case let url as URL in en
        where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            out.append(FileEntry(url: url, mtime: m))
        }
        return out
    }

    /// 从单个文件里取"最后一条"非空 rate_limits(文件是追加写,越靠后越新)
    static func latestRateLimits(in url: URL) -> ToolQuota? {
        // rollout 可能几十到几百 MB;额度在最近的 token_count 行里,只读文件尾部。
        let maxTailBytes: UInt64 = 2 * 1024 * 1024
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > maxTailBytes ? end - maxTailBytes : 0
        do { try handle.seek(toOffset: start) } catch { return nil }
        guard var data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        // 从文件中间截取时首行通常不完整,丢到第一个换行符为止。
        if start > 0 {
            guard let newline = data.firstIndex(of: 0x0A) else { return nil }
            data.removeSubrange(data.startIndex...newline)
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("rate_limits"),
                  let d = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let rl = (payload["rate_limits"] as? [String: Any])
                    ?? ((payload["info"] as? [String: Any])?["rate_limits"] as? [String: Any]),
                  !rl.isEmpty else { continue }
            let ts = (obj["timestamp"] as? String).flatMap(Self.parseTS) ?? Date()
            return Self.build(rateLimits: rl, asOf: ts)
        }
        return nil
    }

    private static func build(rateLimits rl: [String: Any], asOf: Date) -> ToolQuota? {
        var windows: [QuotaWindow] = []
        func window(_ key: String, kindFallback: QuotaKind) -> QuotaWindow? {
            guard let w = rl[key] as? [String: Any],
                  let used = (w["used_percent"] as? NSNumber)?.doubleValue,
                  let resetUnix = (w["resets_at"] as? NSNumber)?.doubleValue else { return nil }
            let wm = (w["window_minutes"] as? NSNumber)?.intValue
            let kind: QuotaKind = wm == 300 ? .fiveHour : (wm == 10080 ? .weekly : kindFallback)
            guard used.isFinite, resetUnix.isFinite else { return nil }
            return QuotaWindow(tool: .codex, kind: kind, usedPercent: min(100, max(0, used)),
                               resetsAt: Date(timeIntervalSince1970: resetUnix), asOf: asOf)
        }
        if let p = window("primary", kindFallback: .fiveHour) { windows.append(p) }
        if let s = window("secondary", kindFallback: .weekly) { windows.append(s) }
        guard !windows.isEmpty else { return nil }
        let plan = rl["plan_type"] as? String
        return ToolQuota(tool: .codex, plan: plan, windows: windows, authoritative: true, asOf: asOf)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static func parseTS(_ s: String) -> Date? { iso.date(from: s) ?? isoPlain.date(from: s) }
}
