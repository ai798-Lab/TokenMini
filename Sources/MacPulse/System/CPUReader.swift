import Foundation
import Darwin

/// CPU 使用率读取器:每核走 host_processor_info,总量走 host_statistics,均为累计 ticks 两次采样做差。
/// 状态只在 SystemMonitor 的 sampleQueue 上读写,无需加锁。
struct CPUReader {
    // host_processor_info 的缓冲区由内核 vm_allocate,必须由调用方 vm_deallocate,
    // 这里保留上一次的缓冲区做差,换代时释放旧的,否则稳定泄漏
    private var prevCoreInfo: processor_info_array_t?
    private var prevCoreInfoCount: mach_msg_type_number_t = 0
    private var prevCoreCount: natural_t = 0
    private var prevLoad: host_cpu_load_info?

    mutating func read() -> CPUSnapshot {
        var snapshot = CPUSnapshot()

        // MARK: 每核使用率

        var coreCount: natural_t = 0
        var coreInfo: processor_info_array_t?
        var coreInfoCount: mach_msg_type_number_t = 0
        let coreResult = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                             &coreCount, &coreInfo, &coreInfoCount)
        if coreResult == KERN_SUCCESS, let coreInfo {
            // 核数变化(理论上不会发生)时旧数据无法对齐,按首次处理
            if let prev = prevCoreInfo, prevCoreCount == coreCount {
                var perCore: [Double] = []
                perCore.reserveCapacity(Int(coreCount))
                for i in 0..<Int(coreCount) {
                    let base = Int(CPU_STATE_MAX) * i
                    // 累计计数器,&- 防溢出环绕导致崩溃
                    let user = coreInfo[base + Int(CPU_STATE_USER)] &- prev[base + Int(CPU_STATE_USER)]
                    let system = coreInfo[base + Int(CPU_STATE_SYSTEM)] &- prev[base + Int(CPU_STATE_SYSTEM)]
                    let nice = coreInfo[base + Int(CPU_STATE_NICE)] &- prev[base + Int(CPU_STATE_NICE)]
                    let idle = coreInfo[base + Int(CPU_STATE_IDLE)] &- prev[base + Int(CPU_STATE_IDLE)]
                    let inUse = Double(user) + Double(system) + Double(nice)
                    let total = inUse + Double(idle)
                    let usage = total > 0 ? inUse / total : 0
                    perCore.append(min(max(usage, 0), 1))
                }
                snapshot.perCore = perCore
            } else {
                snapshot.perCore = Array(repeating: 0, count: Int(coreCount))
            }
            if let prev = prevCoreInfo {
                let size = vm_size_t(Int(prevCoreInfoCount) * MemoryLayout<integer_t>.stride)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), size)
            }
            prevCoreInfo = coreInfo
            prevCoreInfoCount = coreInfoCount
            prevCoreCount = coreCount
        }

        // MARK: 总量 user/system

        if let load = Self.hostCPULoadInfo() {
            if let prev = prevLoad {
                // cpu_ticks: .0=USER .1=SYSTEM .2=IDLE .3=NICE
                let user = Double(load.cpu_ticks.0 &- prev.cpu_ticks.0)
                let system = Double(load.cpu_ticks.1 &- prev.cpu_ticks.1)
                let idle = Double(load.cpu_ticks.2 &- prev.cpu_ticks.2)
                let nice = Double(load.cpu_ticks.3 &- prev.cpu_ticks.3)
                let total = user + system + idle + nice
                if total > 0 {
                    // NICE 仍是用户态工作;总量若漏掉它会低于每核使用率。
                    snapshot.userUsage = (user + nice) / total
                    snapshot.systemUsage = system / total
                    snapshot.totalUsage = min((user + nice + system) / total, 1)
                }
            }
            prevLoad = load
        }
        return snapshot
    }

    private static func hostCPULoadInfo() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}
