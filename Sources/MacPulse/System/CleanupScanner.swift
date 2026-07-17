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
/// 5. 删不动的(正被占用)静默跳过并计入 failedCount,不影响其它项。
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

    func scan() -> [CleanupScanResult] {
        var out: [CleanupScanResult] = []
        for category in CleanupCategory.allCases {
            var items: [CleanupItem] = []
            for root in allowedRoots(for: category) {
                items.append(contentsOf: Self.breakdown(ofRoot: root))
            }
            let total = items.reduce(Int64(0)) { $0 + $1.bytes }
            out.append(CleanupScanResult(category: category, totalBytes: total, items: items))
        }
        return out
    }

    /// 枚举根目录下的顶层子项(文件/目录/符号链接都要,含隐藏项),逐项算体积。
    /// 不用 `du -d 1`——它只列子目录、漏掉顶层松散文件(.Trash/日志常是文件),
    /// 且 macOS 上 `-a` 与 `-d` 互斥。改用 FileManager 枚举 + 每项 `du -sk`(并行)。
    private static func breakdown(ofRoot root: String) -> [CleanupItem] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        var rootInfo = stat()
        guard lstat(root, &rootInfo) == 0,
              (rootInfo.st_mode & S_IFMT) != S_IFLNK,
              fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { return [] }

        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []) else { return [] }
        guard !children.isEmpty else { return [] }

        let lock = NSLock()
        var items: [CleanupItem] = []
        // 每项独立 du,并行加速(7GB 缓存串行要十几秒)
        DispatchQueue.concurrentPerform(iterations: children.count) { i in
            let url = children[i]
            // 符号链接记 0 且不跟随:只删链接本身,绝不遍历/触碰目标
            let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            let bytes = isSymlink ? 0 : duSize(of: url.path)
            let item = CleanupItem(path: url.path, bytes: bytes)
            lock.lock(); items.append(item); lock.unlock()
        }
        return items
    }

    /// 单项体积(KB→字节)。du 默认不跟随符号链接,对文件/目录都适用。
    private static func duSize(of path: String) -> Int64 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        task.arguments = ["-s", "-k", path]           // 路径作单一参数,空格安全
        task.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return 0 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8),
              let tab = text.firstIndex(of: "\t"),
              let kb = Int64(text[text.startIndex..<tab]) else { return 0 }
        return kb * 1024
    }

    // MARK: - 清理

    func clean(categories: Set<CleanupCategory>, scan results: [CleanupScanResult]) -> CleanupReport {
        var report = CleanupReport()
        let fm = FileManager.default
        for result in results where categories.contains(result.category) {
            for item in result.items {
                guard isSafeToDelete(item.path) else {
                    report.failedCount += 1
                    continue
                }
                do {
                    try fm.removeItem(atPath: item.path)   // 删符号链接只删链接,不动目标
                    report.freedBytes += item.bytes
                    report.deletedCount += 1
                } catch {
                    report.failedCount += 1                // 正被占用等,跳过
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
