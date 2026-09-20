import Foundation

/// 垃圾清理:扫描可再生缓存目录、按类目算体积、安全删除其内容。
///
/// 安全模型(删文件,必须防呆)——
/// 1. 白名单:只处理 allowedRoots 里写死的、全部由 home 目录拼出的缓存路径;
///    绝不含 Documents/Desktop/Downloads、Library/Application Support、Preferences、
///    pnpm store(node_modules 硬链接源)等重要目录。
/// 2. 只删各根目录的「内容」(顶层子项),不删根目录本身。
/// 3. 每次 removeItem 前过 isSafeToDelete 三重守卫(在 home 下、在某白名单根下、不在保护名单)。
/// 4. 删的是扫描时列出的具体项;删符号链接只删链接不动目标。
/// 5. 删除失败保留具体原因，不把权限错误当成占用。
///
/// 线程契约:scan/clean 只在后台队列调用,不碰 UI 状态。
final class CleanupScanner: @unchecked Sendable {

    private let home: String

    init(homeDirectory: String = NSHomeDirectory()) {
        home = Self.standardized(homeDirectory)
    }

    /// 每个类目对应的根目录(其「内容」可删)。不存在的目录扫描时自动跳过。
    func allowedRoots(for category: CleanupCategory) -> [String] {
        switch category {
        case .trash:
            return [home + "/.Trash"]
        case .appCaches:
            return [home + "/Library/Caches"]
        case .userLogs:
            return [home + "/Library/Logs"]
        case .devCaches:
            return [home + "/.npm/_cacache",
                    home + "/Library/Developer/Xcode/DerivedData",
                    home + "/Library/Developer/Xcode/iOS DeviceSupport"]
        }
    }

    /// 所有白名单根(供 isSafeToDelete 校验删除项的归属)
    private var allAllowedRoots: [String] {
        CleanupCategory.allCases.flatMap { allowedRoots(for: $0) }
            .map { Self.standardized($0) }
    }

    /// 永不允许触碰的保护目录(即便某天白名单写错也兜底拦下)。
    /// 注意:不能把 home 本身放进来——守卫第 3 关用 `hasPrefix(prot + "/")` 匹配,
    /// 放了 home 会把 home 下所有路径全拒(删 home 本身已由第 1 关的 p != home 挡住)。
    private var protectedPaths: [String] {
        return [home + "/Documents", home + "/Desktop", home + "/Downloads",
                home + "/Movies", home + "/Music", home + "/Pictures",
                home + "/Library/Preferences",
                home + "/Library/Application Support",
                home + "/Library/Mobile Documents",   // iCloud Drive
                home + "/Library/Keychains",
                home + "/Library/pnpm/store",          // 被 node_modules 硬链接引用
                home + "/.ssh", home + "/.gnupg"]
    }

    // MARK: - 扫描

    func scan(cancelled: () -> Bool = { false },
              progress: (CleanupCategory) -> Void = { _ in }) -> [CleanupScanResult] {
        var out: [CleanupScanResult] = []
        for category in CleanupCategory.allCases {
            if cancelled() { break }
            progress(category)
            let deadline = Date().addingTimeInterval(45)
            var items: [CleanupItem] = []
            var issues: [CleanupIssue] = []
            for root in allowedRoots(for: category) {
                if cancelled() { break }
                if Self.hasSymlinkComponent(from: home, through: root) {
                    issues.append(CleanupIssue(path: root, message: "目录经过符号链接，已跳过以保护目标文件"))
                    continue
                }
                do {
                    let children = try FileManager.default.contentsOfDirectory(
                        at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)
                    let lock = NSLock()
                    var next = 0
                    var rootItems: [CleanupItem] = []
                    var rootIssues: [CleanupIssue] = []
                    let sorted = children.sorted { $0.lastPathComponent < $1.lastPathComponent }
                    // 最多 4 个测量进程，避免逐项等待权限超时，也避免旧版无界并行启动 du。
                    DispatchQueue.concurrentPerform(iterations: min(4, sorted.count)) { _ in
                        while !cancelled() {
                            lock.lock()
                            guard next < sorted.count else { lock.unlock(); break }
                            let url = sorted[next]
                            next += 1
                            lock.unlock()
                            if Date() > deadline {
                                lock.lock()
                                if !rootIssues.contains(where: { $0.path == root }) {
                                    rootIssues.append(CleanupIssue(path: root, message: "扫描超过时限，结果不完整；可重新扫描"))
                                }
                                lock.unlock()
                                break
                            }
                            do {
                                // 保留白名单根的词法路径，避免 /var 与 /private/var 的 URL 重写。
                                let candidate = root + "/" + url.lastPathComponent
                                let identity = try Self.identity(at: candidate)
                                let bytes = try Self.allocatedSize(url, deadline: deadline, cancelled: cancelled)
                                lock.lock()
                                rootItems.append(CleanupItem(path: candidate, bytes: bytes, identity: identity))
                                lock.unlock()
                            } catch {
                                lock.lock(); rootIssues.append(Self.issue(error, path: url.path)); lock.unlock()
                            }
                        }
                    }
                    items.append(contentsOf: rootItems.sorted { $0.path < $1.path })
                    issues.append(contentsOf: rootIssues.sorted { $0.path < $1.path })
                } catch {
                    let ns = error as NSError
                    // 缺失的可选缓存目录不是错误；权限拒绝绝不能伪装成空目录。
                    if !(ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError) {
                        issues.append(Self.issue(error, path: root))
                    }
                }
            }
            out.append(CleanupScanResult(category: category,
                totalBytes: items.reduce(0) { $0 + $1.bytes }, items: items, issues: issues))
        }
        return out
    }

    private static func identity(at path: String) throws -> CleanupIdentity {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return CleanupIdentity(device: info.st_dev, inode: info.st_ino,
            modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanoseconds: info.st_mtimespec.tv_nsec)
    }

    /// du 默认不跟随符号链接。每项独立子进程，系统访问请求阻塞时也可超时或取消。
    /// 不在应用进程里递归枚举：TCC 拦截 open() 时，线程内的取消标记无法生效。
    private static func allocatedSize(_ url: URL, deadline: Date, cancelled: () -> Bool) throws -> Int64 {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if (info.st_mode & S_IFMT) == S_IFLNK { return 0 }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        task.arguments = ["-s", "-k", url.path]
        task.environment = ["LC_ALL": "C"]
        let output = Pipe()
        task.standardOutput = output
        // stderr 写临时文件避免大量权限错误塞满管道；只读取前 8KB，不把原始路径输出到日志。
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-scan-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let errors = try FileHandle(forWritingTo: errorURL)
        defer { try? errors.close(); try? FileManager.default.removeItem(at: errorURL) }
        task.standardError = errors
        try task.run()
        let itemDeadline = min(deadline, Date().addingTimeInterval(8))
        while task.isRunning {
            if cancelled() || Date() > itemDeadline {
                task.terminate()
                // 仅终止本次创建的 du；避免被权限提示卡住后永远占用扫描队列。
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                task.waitUntilExit()
                if cancelled() { throw CocoaError(.userCancelled) }
                throw NSError(domain: "MacPulse", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "读取超时（可能等待系统访问许可），已跳过。请检查权限后重新扫描。"])
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        task.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if task.terminationStatus != 0 {
            let reader = try FileHandle(forReadingFrom: errorURL)
            defer { try? reader.close() }
            let message = String(data: try reader.read(upToCount: 8192) ?? Data(), encoding: .utf8) ?? ""
            if message.contains("Operation not permitted") || message.contains("Permission denied") {
                throw CocoaError(.fileReadNoPermission)
            }
            throw NSError(domain: "MacPulse", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "体积未完整读取，目录可能在扫描期间变化；请重新扫描"])
        }
        guard let text = String(data: data, encoding: .utf8),
              let first = text.split(separator: "\t").first,
              let kb = Int64(first.trimmingCharacters(in: .whitespacesAndNewlines)), kb >= 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return kb * 1024
    }

    private static func issue(_ error: Error, path: String) -> CleanupIssue {
        let ns = error as NSError
        let denied = (ns.domain == NSCocoaErrorDomain &&
            [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(ns.code)) ||
            (ns.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(ns.code))
        return CleanupIssue(path: path,
            message: denied ? "macOS 拒绝访问，请检查完整磁盘访问权限或文件权限" : error.localizedDescription,
            permissionDenied: denied)
    }

    // MARK: - 清理

    func clean(categories: Set<CleanupCategory>, scan results: [CleanupScanResult],
               selectedPaths: Set<String>? = nil) -> CleanupReport {
        var report = CleanupReport()
        var seen = Set<String>()
        for result in results where categories.contains(result.category) {
            for item in result.items where selectedPaths?.contains(item.path) ?? true {
                guard seen.insert(item.path).inserted else { continue }
                guard isSafeToDelete(item.path),
                      allowedRoots(for: result.category).contains((item.path as NSString).deletingLastPathComponent) else {
                    report.failedCount += 1
                    report.issues.append(CleanupIssue(path: item.path, message: "路径未通过安全校验"))
                    continue
                }
                do {
                    let current = try Self.identity(at: item.path)
                    guard let expected = item.identity, expected == current else {
                        report.failedCount += 1
                        report.issues.append(CleanupIssue(path: item.path, message: "文件在扫描后发生变化，请重新扫描后确认"))
                        continue
                    }
                    try FileManager.default.removeItem(atPath: item.path)
                    report.freedBytes += item.bytes
                    report.deletedCount += 1
                } catch {
                    let ns = error as NSError
                    if (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT)) ||
                        (ns.domain == NSCocoaErrorDomain && ns.code == NSFileNoSuchFileError) {
                        report.missingCount += 1
                    } else {
                        report.failedCount += 1
                        report.issues.append(Self.issue(error, path: item.path))
                    }
                }
            }
        }
        return report
    }

    /// 三重守卫:严格在 home 下 + 归属某白名单根 + 不命中保护目录。
    /// 任何一条不满足都拒删。
    static func isSafeToDelete(_ path: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        CleanupScanner(homeDirectory: homeDirectory).isSafeToDelete(path)
    }

    private func isSafeToDelete(_ path: String) -> Bool {
        let p = Self.standardized(path)

        // 1) 必须严格在 home 目录之下(且不等于 home)
        guard p.hasPrefix(home + "/"), p != home else { return false }

        // 2) 只能删白名单根的直接子项,不能接受更深层路径;同时白名单根到 home
        // 之间任一组件都不能是符号链接,避免 `~/Library/Caches -> 外部目录` 后误删目标。
        let parent = (p as NSString).deletingLastPathComponent
        guard let root = allAllowedRoots.first(where: { $0 == parent }),
              !Self.hasSymlinkComponent(from: home, through: root) else { return false }

        // 3) 不得等于或位于任何保护目录之下
        for protected in protectedPaths where p == protected || p.hasPrefix(protected + "/") {
            return false
        }
        return true
    }

    /// 用 lstat 只观察路径组件自身,不解析链接目标。候选项本身不在检查范围内——
    /// 它可以是符号链接,removeItem 会只删除链接;必须拦的是候选项的父链。
    private static func hasSymlinkComponent(from home: String, through root: String) -> Bool {
        guard root == home || root.hasPrefix(home + "/") else { return true }
        var current = home
        let suffix = root.dropFirst(home.count)
        for component in suffix.split(separator: "/") {
            current += "/" + component
            var info = stat()
            if lstat(current, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
                return true
            }
        }
        return false
    }

    /// 纯词法归一化:解析 `.`/`..`、去多余斜杠。
    /// 必须词法处理——不能用 NSString.standardizingPath,它会访问文件系统解析
    /// 符号链接/firmlink,对存在与不存在的路径行为不一致,破坏前缀比较。
    private static func standardized(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        var stack: [Substring] = []
        for comp in path.split(separator: "/", omittingEmptySubsequences: true) {
            if comp == "." { continue }
            if comp == ".." {
                if let last = stack.last, last != ".." { stack.removeLast() }
                else if !isAbsolute { stack.append("..") }
                // 绝对路径下 .. 越过根:丢弃
            } else {
                stack.append(comp)
            }
        }
        return (isAbsolute ? "/" : "") + stack.joined(separator: "/")
    }
}
