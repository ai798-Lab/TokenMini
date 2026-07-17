import Foundation

/// Top 进程读取器:shell 出 /bin/ps 解析文本(没有公开 API 能拿到现成的 %CPU)。
/// 沙盒环境不可用,本 app 走非沙盒发行。
enum ProcessReader {
    enum SortBy {
        case cpu       // ps -r
        case memory    // ps -m
        var flag: String { self == .cpu ? "-r" : "-m" }
    }

    static func topProcesses(limit: Int, sortBy: SortBy = .cpu) -> [TopProcess] {
        guard limit > 0 else { return [] }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        // -c 让 comm 只输出可执行名(不带路径参数),-r 按 CPU 降序 / -m 按内存降序
        task.arguments = ["-Aceo", "pid,pcpu,rss,comm", sortBy.flag]
        // 固定 C locale,避免欧洲 locale 下 pcpu 打出逗号小数点
        task.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return []
        }
        // 先读完再 waitUntilExit,反过来输出超过管道缓冲区会死锁
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var result: [TopProcess] = []
        for line in output.split(separator: "\n") {
            if result.count >= limit { break }
            // comm 可能含空格,只切前 3 列,剩余整段作为进程名
            let parts = line.split(maxSplits: 3, omittingEmptySubsequences: true,
                                   whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = UInt64(parts[2]) else { continue }   // 表头与异常行在此跳过
            let comm = parts[3].trimmingCharacters(in: .whitespaces)
            guard !comm.isEmpty else { continue }
            let name = (comm as NSString).lastPathComponent
            result.append(TopProcess(pid: pid,
                                     name: name.isEmpty ? comm : name,
                                     cpuPercent: cpu,
                                     memoryBytes: rssKB &* 1024))
        }
        return result
    }

    /// 结束进程前重新核对 PID 当前对应的可执行名,降低采样后 PID 被复用而误杀的风险。
    static func name(of pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", String(pid), "-o", "comm="]
        task.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let basename = (raw as NSString).lastPathComponent
        return basename.isEmpty ? raw : basename
    }
}
