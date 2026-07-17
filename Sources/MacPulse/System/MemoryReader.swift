import Foundation
import Darwin

/// 内存读取器:host_statistics64(HOST_VM_INFO64) 页计数 × vm_page_size,口径对齐活动监视器。
struct MemoryReader {
    // 物理内存总量不变,构造时读一次
    private let total: UInt64 = {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &value, &size, nil, 0)
        return value
    }()

    func read() -> MemorySnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return MemorySnapshot() }

        // Apple Silicon 页大小是 16384,必须用全局 vm_page_size,不能硬编码 4096
        let page = UInt64(vm_page_size)
        let active = UInt64(stats.active_count) * page
        let inactive = UInt64(stats.inactive_count) * page
        let speculative = UInt64(stats.speculative_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let purgeable = UInt64(stats.purgeable_count) * page
        let external = UInt64(stats.external_page_count) * page

        // 活动监视器口径:不是 total - free,要减掉 purgeable 和 file-backed(external)
        let usedSigned = Int64(active &+ inactive &+ speculative &+ wired &+ compressed)
            - Int64(purgeable) - Int64(external)
        let used = UInt64(max(usedSigned, 0))

        var snapshot = MemorySnapshot()
        snapshot.total = total
        snapshot.used = min(used, total)
        snapshot.wired = wired
        snapshot.compressed = compressed
        snapshot.free = total > used ? total - used : 0
        snapshot.pressure = Self.readPressure()
        return snapshot
    }

    /// macOS memorystatus 的真实压力级别:1=正常、2=警告、4=危急。
    /// 高内存占用在 macOS 上常常只是文件缓存,不能拿 used/total 冒充压力告警。
    private static func readPressure() -> Double {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return 0
        }
        if level >= 4 { return 1 }
        if level >= 2 { return 0.85 }
        return 0
    }
}
