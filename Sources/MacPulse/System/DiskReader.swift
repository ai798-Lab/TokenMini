import Foundation
import IOKit

/// 磁盘吞吐读取器:汇总所有 IOBlockStorageDriver 的 Statistics 累计读写字节,两次采样差值 / 间隔。
/// Statistics 挂在驱动上而不是 IOMedia 上,直接匹配驱动类即可,不必从卷沿 IORegistry 向上找;
/// 数值是整个物理盘的累计值,不区分卷。
struct DiskReader {
    private var prevRead: Int64 = 0
    private var prevWrite: Int64 = 0
    private var prevTime: TimeInterval = 0
    private var hasPrev = false

    mutating func read() -> DiskSnapshot {
        let now = Date().timeIntervalSinceReferenceDate
        // 瞬时失败(匹配服务出错)不能当成 (0,0) 写进基准——否则下一 tick 的
        // delta = 真实累计值 - 0,会显示数百 GB/s 级的虚假尖峰。失败就跳过本轮、保留旧基准。
        guard let (readBytes, writeBytes) = Self.readCounters() else { return DiskSnapshot() }
        defer {
            prevRead = readBytes
            prevWrite = writeBytes
            prevTime = now
            hasPrev = true
        }
        guard hasPrev else { return DiskSnapshot() }
        let elapsed = now - prevTime
        guard elapsed > 0 else { return DiskSnapshot() }

        // 外置盘弹出等会让累计总和变小,负差值归零
        let readDelta = max(readBytes - prevRead, 0)
        let writeDelta = max(writeBytes - prevWrite, 0)
        return DiskSnapshot(readPerSec: Double(readDelta) / elapsed,
                            writePerSec: Double(writeDelta) / elapsed)
    }

    private static func readCounters() -> (read: Int64, write: Int64)? {
        var iterator: io_iterator_t = 0
        // kIOMainPortDefault 需要 macOS 12+,本项目最低 14,直接用
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var readTotal: Int64 = 0
        var writeTotal: Int64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let stats = props["Statistics"] as? [String: Any] else { continue }
            readTotal &+= (stats["Bytes (Read)"] as? NSNumber)?.int64Value ?? 0
            writeTotal &+= (stats["Bytes (Write)"] as? NSNumber)?.int64Value ?? 0
        }
        return (readTotal, writeTotal)
    }
}
