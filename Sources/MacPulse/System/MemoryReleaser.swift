import Foundation
import Darwin

/// 内存回收:申请并触碰一块内存促使系统把其它进程的非活跃内存压缩/换出,随即释放,
/// 让「空闲」上升。这是 macOS 上免 root 的唯一途径(purge 需要 root)。
///
/// 诚实说明:现代 macOS(尤其 Apple Silicon)内存管理与压缩已经很好,
/// 「回收」多数时候只是把非活跃内存转成空闲、数字变好看,实际提速有限;
/// 真正释放内存的办法是结束不用的应用(见进程列表的「结束」)。
///
/// 安全:申请量封顶 3GB 且不超过当前空闲的一半,分块 mmap,后台执行,不会造成内存压力。
enum MemoryReleaser {

    /// 返回「空闲内存」净增字节数(可能为 0——系统本就无可回收)
    static func release() -> Int64 {
        let before = freeBytes()
        // 不超过空闲一半,封顶 3GB;空闲太少就不做(避免制造压力)
        let target = min(Int(3) << 30, Int(before / 2))
        guard target > (64 << 20) else { return 0 }

        let chunkSize = 256 << 20
        let page = Int(vm_page_size)
        var chunks: [(ptr: UnsafeMutableRawPointer, size: Int)] = []
        var allocated = 0

        while allocated < target {
            let size = min(chunkSize, target - allocated)
            let ptr = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0)
            guard let ptr, ptr != MAP_FAILED else { break }
            // 逐页写一个字节,强制物理驻留(仅 mmap 不会真正占用物理页)
            var off = 0
            while off < size {
                ptr.storeBytes(of: 1, toByteOffset: off, as: UInt8.self)
                off += page
            }
            chunks.append((ptr, size))
            allocated += size
        }
        // munmap 保证把物理页立刻还给系统
        for c in chunks { munmap(c.ptr, c.size) }

        let after = freeBytes()
        return max(0, after - before)
    }

    /// 当前空闲内存(free + purgeable,字节)
    private static func freeBytes() -> Int64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = Int64(vm_page_size)
        return (Int64(stats.free_count) + Int64(stats.purgeable_count)) * page
    }
}
