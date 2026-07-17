import Foundation

/// 磁盘可用空间读取器:读数据卷的容量与「重要用途可用空间」(Finder 显示口径)。
struct DiskSpaceReader {
    func read() -> DiskSpaceSnapshot {
        var snap = DiskSpaceSnapshot()
        let url = URL(fileURLWithPath: "/")
        guard let vals = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { return snap }
        if let total = vals.volumeTotalCapacity { snap.total = UInt64(max(0, total)) }
        // ForImportantUsage 是 Int64,反映清完可清理项后实际可用,与 Finder 一致
        if let free = vals.volumeAvailableCapacityForImportantUsage { snap.free = UInt64(max(0, free)) }
        return snap
    }
}
